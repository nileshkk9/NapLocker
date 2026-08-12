import AppKit
import SwiftUI

/// Visual state of the lock overlay.
enum OverlayState {
    /// Authentication in progress (system Touch ID sheet is up).
    case authenticating
    /// The last attempt failed or was cancelled; offer retry / quit.
    case failed
}

/// Presents an opaque cover over the whole screen while a protected app is being
/// unlocked, so the target app's content is never visible (Option B). Abstracted
/// so `LockManager` can be tested without real windows.
@MainActor
protocol OverlayPresenting: AnyObject {
    func present(appName: String, onUnlock: @escaping () -> Void, onQuit: @escaping () -> Void)
    func setState(_ state: OverlayState)
    func dismiss()
}

/// Backing model shared with `LockOverlayView` so button taps and state changes
/// flow through a single object.
@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var appName: String = ""
    @Published var state: OverlayState = .authenticating
    var onUnlock: () -> Void = {}
    var onQuit: () -> Void = {}
}

/// Places a borderless, opaque `NSWindow` at `.screenSaver` level on every
/// screen. The high window level plus `canJoinAllSpaces` keeps the cover on top
/// of the launching app, including in full-screen Spaces.
@MainActor
final class LockOverlayController: OverlayPresenting {
    private var windows: [NSWindow] = []
    private let model = OverlayViewModel()

    func present(appName: String, onUnlock: @escaping () -> Void, onQuit: @escaping () -> Void) {
        model.appName = appName
        model.onUnlock = onUnlock
        model.onQuit = onQuit
        model.state = .authenticating

        // Reuse existing windows if the overlay is already up.
        if windows.isEmpty {
            for screen in NSScreen.screens {
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
                window.ignoresMouseEvents = false
                window.contentViewController = NSHostingController(rootView: LockOverlayView(model: model))
                window.setFrame(screen.frame, display: true)
                window.makeKeyAndOrderFront(nil)
                windows.append(window)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func setState(_ state: OverlayState) {
        model.state = state
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
