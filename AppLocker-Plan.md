# macOS AppLocker — Implementation Plan

> A lightweight menu bar utility that requires Touch ID (or password) authentication when a protected app is **freshly launched**. Minimizing and restoring an already-authenticated app does **not** re-prompt.

---

## 1. Goals & Scope

### In Scope
- Lock an arbitrary number of user-installed macOS apps.
- Authenticate unlock via **Touch ID / Face ID**, with system password fallback.
- Prompt **only on fresh launch** — not on unminimize, window focus, or Cmd-Tab.
- Menu bar UI for managing the locked-app list.
- Persist the locked-app list across reboots.

### Out of Scope (v1)
- Persistent background lock daemon.
- Locking SIP-protected / system processes.
- Per-app time limits or scheduling.
- iCloud sync of settings.

---

## 2. Behavior Specification

| Event | Behavior |
|---|---|
| Protected app freshly launched | Show authentication prompt |
| Auth succeeds | App runs freely for the rest of its lifetime |
| Auth fails / cancelled | App is terminated |
| App minimized → restored | No prompt |
| App backgrounded → foregrounded | No prompt |
| App quit and relaunched | Prompt again |
| Non-protected app launched | Ignored |

**Key insight:** `NSWorkspace.didLaunchApplicationNotification` fires only on fresh process launch, giving us the desired "once per launch" behavior with no extra state tracking.

---

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│              Menu Bar App (SwiftUI)           │
│                                               │
│  ┌────────────┐   ┌────────────────────────┐ │
│  │  Settings   │   │   LockManager           │ │
│  │  UI         │   │  - locked app list      │ │
│  │  (add/remove│◄──┤  - persistence          │ │
│  │   apps)     │   │  - launch observer      │ │
│  └────────────┘   └───────────┬────────────┘ │
│                                │              │
│                    ┌───────────▼───────────┐  │
│                    │  NSWorkspace observer  │  │
│                    │  (didLaunchApplication)│  │
│                    └───────────┬───────────┘  │
│                                │              │
│                    ┌───────────▼───────────┐  │
│                    │  AuthController        │  │
│                    │  (LocalAuthentication) │  │
│                    └───────────┬───────────┘  │
│                                │              │
│              ┌─────────────────┴──────────┐  │
│         success                     failure  │
│              │                          │    │
│      let app run              terminate app  │
└─────────────────────────────────────────────┘
```

---

## 4. Component Breakdown

### 4.1 `LockManager`
- Holds the set of protected apps (by **bundle identifier**, e.g. `com.apple.Safari`).
- Loads/saves the list to `UserDefaults` (or JSON in `~/Library/Application Support/AppLocker/`).
- Registers as observer of `NSWorkspace.shared.notificationCenter`.

### 4.2 Launch Observer
- Subscribes to `NSWorkspace.didLaunchApplicationNotification`.
- Extracts the launched app's `NSRunningApplication` from the notification `userInfo`.
- Checks `bundleIdentifier` against the protected set.
- If matched → hand off to `AuthController`.

### 4.3 `AuthController`
- Uses `LAContext` from the `LocalAuthentication` framework.
- Policy: `.deviceOwnerAuthentication` (Touch ID with password fallback).
- On success: no-op (let the app continue).
- On failure/cancel: call `runningApp.terminate()` (or `.forceTerminate()` if needed).

### 4.4 Menu Bar UI (SwiftUI)
- `MenuBarExtra` (macOS 13+) or `NSStatusItem` (older).
- Views:
  - **Locked Apps list** — shows current protected apps with remove buttons.
  - **Add App** — file picker into `/Applications`, resolves selected `.app` → bundle ID.
  - **Toggle** — global enable/disable.
  - **Quit**.

---

## 5. Permissions Required

| Permission | Why | How Granted |
|---|---|---|
| **Accessibility** (optional) | Smoother lock overlay / reliable termination | System Settings → Privacy → Accessibility |
| **Touch ID entitlement** | Use biometric auth | Automatic via `LocalAuthentication` |
| **App Sandbox: OFF** (recommended for v1) | Terminate other processes & observe launches | Signing config |

> Note: Observing `NSWorkspace` launch notifications and terminating other apps works without Accessibility in most cases, but Accessibility makes the overlay approach (Section 8) more reliable.

---

## 6. Technology Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI + `MenuBarExtra` |
| Auth | `LocalAuthentication` (`LAContext`) |
| App detection | `NSWorkspace` notifications |
| Persistence | `UserDefaults` / JSON file |
| Build | Xcode 15+ |
| Min target | macOS 13 Ventura |

---

## 7. Implementation Phases

### Phase 1 — Project Skeleton (Day 1)
- [ ] Create Xcode macOS app project (SwiftUI lifecycle).
- [ ] Configure as menu bar / agent app (`LSUIElement = YES` — no Dock icon).
- [ ] Basic `MenuBarExtra` with a placeholder menu.

### Phase 2 — Lock List Management (Days 2-3)
- [ ] `LockManager` model with add/remove/persist.
- [ ] Settings UI: list protected apps, add via file picker, remove.
- [ ] Resolve `.app` bundle → `bundleIdentifier`.

### Phase 3 — Launch Detection (Days 4-5)
- [ ] Subscribe to `didLaunchApplicationNotification`.
- [ ] Match launched app against protected set.
- [ ] Log detection (temporary) to verify correctness.

### Phase 4 — Authentication (Days 6-7)
- [ ] `AuthController` with `LAContext`.
- [ ] Trigger Touch ID prompt on protected-app launch.
- [ ] Terminate app on failure; allow on success.

### Phase 5 — Polish (Days 8-10)
- [ ] Handle edge cases (app already running at startup, rapid relaunch).
- [ ] Global enable/disable toggle.
- [ ] Launch-at-login option (`SMAppService`).
- [ ] App icon, menu bar icon, basic branding.

### Phase 6 — Hardening (Optional, Days 11-14)
- [ ] Overlay lock window (Section 8) for a flash-free experience.
- [ ] Prevent trivial bypass (e.g., quitting AppLocker itself — optional self-protection).
- [ ] Code signing + notarization for distribution.

---

## 8. Locking Strategy — Two Options

### Option A — Kill-on-Fail (Simplest, v1 default)
1. App launches → Touch ID prompt appears.
2. The target app is briefly visible behind the prompt.
3. Fail → terminate. Pass → dismiss prompt.

**Pro:** Minimal code. **Con:** Target app flashes visible for ~100-300ms.

### Option B — Overlay Window (Polished)
1. App launches → immediately place a full-screen `NSWindow` (`.screenSaver` level) over it.
2. Overlay hosts the Touch ID prompt.
3. Pass → remove overlay. Fail → terminate app + remove overlay.

**Pro:** No visible target content. **Con:** More window-management code; benefits from Accessibility permission.

> **Recommendation:** Ship Option A in v1, upgrade to Option B in Phase 6.

---

## 9. Known Limitations

- **Launch flash** (~100-300ms) in Option A — unavoidable without a kernel extension (Apple no longer permits these for this use case).
- **SIP-protected processes** cannot be interfered with — not a concern for normal user apps.
- **Root-owned apps** would need a privileged helper to terminate — out of scope for v1.
- **Bypass vector:** A technical user could quit AppLocker before launching a locked app. Optional self-protection (relaunch-on-quit) mitigates but doesn't fully prevent this without a daemon.

---

## 10. Distribution Options

| Method | Notes |
|---|---|
| Direct `.app` (notarized) | Requires Apple Developer account ($99/yr) for notarization |
| DMG installer | Standard for indie macOS apps |
| Mac App Store | Sandbox restrictions make app-termination features hard — **not recommended** |

---

## 11. Success Criteria (v1)

- [ ] Can add/remove any number of apps to the locked list.
- [ ] Launching a locked app triggers Touch ID.
- [ ] Correct auth lets the app run; failed auth terminates it.
- [ ] Minimizing/restoring a running locked app does **not** re-prompt.
- [ ] Settings persist across reboots.
- [ ] Runs quietly from the menu bar with no Dock icon.

---

## 12. Estimated Timeline

| Scope | Duration |
|---|---|
| Functional v1 (Option A) | **1 week** |
| Polished v1 (Option B, launch-at-login, branding) | **2 weeks** |
| Distribution-ready (signed, notarized, DMG) | **+2-3 days** |

---

*Next step: scaffold the Xcode project and implement Phase 1-3 (skeleton + lock list + launch detection).*
