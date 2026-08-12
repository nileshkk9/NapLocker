# NapLocker

A minimal macOS menu bar utility that requires **Touch ID / password** authentication when a
**protected app is freshly launched**. Minimizing, refocusing, or Cmd-Tabbing back to an
already-unlocked app does **not** re-prompt — the lock happens once per launch.

## How it works

NapLocker listens for `NSWorkspace.didLaunchApplicationNotification`, which fires only on a
*fresh process launch*. When a protected app launches it:

1. Instantly covers the screen with an opaque overlay (so the app's content never flashes).
2. Requests authentication via `LocalAuthentication` (Touch ID, password fallback).
3. On success, removes the overlay. On cancel/failure, offers **Unlock** (retry) or **Quit App**.

## Architecture

The core (`LockManager`) depends only on protocols, so it is fully unit-tested without AppKit
or real biometrics (Dependency Inversion / SOLID):

| Protocol | Production impl | Responsibility |
|---|---|---|
| `LockListStore` | `JSONFileLockListStore` | Persist protected apps + flags as JSON |
| `LaunchMonitoring` | `WorkspaceLaunchMonitor` | Observe fresh launches via `NSWorkspace` |
| `Authenticating` | `LocalAuthenticator` | Touch ID / password (`LAContext`) |
| `AppTerminating` | `RunningAppTerminator` | Quit → force-quit escalation |
| `OverlayPresenting` | `LockOverlayController` | Opaque screen cover (Option B) |
| `LaunchAtLoginControlling` | `LaunchAtLogin` | `SMAppService` login item |

Wiring lives in `AppDelegate` (the composition root). State is stored at
`~/Library/Application Support/NapLocker/locked-apps.json`.

## Requirements

- **macOS 14+** (uses the Observation framework / `@Observable`).
- **Full Xcode** (this repo ships an `.xcodeproj`; Command Line Tools alone cannot build an app bundle).
  - Install Xcode from the App Store, then: `sudo xcode-select -s /Applications/Xcode.app`

## Build & run

```bash
# From the repo root:
xcodebuild -project NapLocker.xcodeproj -scheme NapLocker -configuration Debug build

# Or open in Xcode and press Run:
open NapLocker.xcodeproj
```

> **Signing:** In Xcode, select the `NapLocker` target → Signing & Capabilities → pick your Team
> (automatic signing). A signed build gives stable biometric behavior.
>
> **Sandbox is intentionally OFF** (`NapLocker.entitlements`) — required to observe other apps
> launching and to terminate them. This means the app is not Mac App Store eligible.

## Test

```bash
xcodebuild -project NapLocker.xcodeproj -scheme NapLocker \
  -destination 'platform=macOS' test
```

## Manual verification

1. Menu bar lock icon appears; no Dock icon (`LSUIElement`).
2. Add **Calculator** via *Add App…*.
3. Quit Calculator, relaunch it → overlay + Touch ID prompt.
4. Cancel → **Quit App** terminates it; **Unlock** retries. Success → overlay clears, app usable.
5. Minimize/restore & Cmd-Tab on the unlocked app → **no** re-prompt.
6. Enable **Launch at Login**, reboot → NapLocker is running and protecting.
7. Settings persist across relaunch.

## Known limitations

- A technical user can quit NapLocker before launching a locked app (no background daemon in v1).
- SIP-protected / root-owned processes are out of scope.
- Distribution (notarization / DMG) is not set up here — local signed runs only.
