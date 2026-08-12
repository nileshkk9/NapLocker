import AppKit

/// Owns the composition root: builds `LockManager` with its production services
/// and starts launch monitoring once the app is ready. Keeping wiring here (not
/// in the SwiftUI `App`) means there is exactly one place that knows the
/// concrete service types.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let lockManager: LockManager = {
        LockManager(
            store: JSONFileLockListStore(),
            monitor: WorkspaceLaunchMonitor(),
            authenticator: LocalAuthenticator(),
            terminator: RunningAppTerminator(),
            overlay: LockOverlayController(),
            launchAtLogin: LaunchAtLogin()
        )
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        lockManager.start()
    }
}
