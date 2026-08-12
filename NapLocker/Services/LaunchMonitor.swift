import AppKit

/// The minimal view of a launched application that `LockManager` needs. Backed
/// by `NSRunningApplication` in production and by a stub in tests, so the core
/// flow never depends on a type we cannot construct in a test.
protocol LaunchedApp {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
}

extension NSRunningApplication: LaunchedApp {}

/// Observes fresh app launches. `LockManager` depends on this abstraction so it
/// can be driven synthetically in tests without a real `NSWorkspace`.
protocol LaunchMonitoring: AnyObject {
    /// Begin delivering a callback for every freshly launched application.
    /// Calling more than once replaces the previous handler.
    func start(onLaunch: @escaping (LaunchedApp) -> Void)
    func stop()
}

/// Bridges `NSWorkspace.didLaunchApplicationNotification` into a simple closure.
///
/// This notification fires **only on a fresh process launch** — not on
/// unminimize, refocus, or Cmd-Tab — which is exactly the "prompt once per
/// launch" behavior we want, with no extra state to track.
final class WorkspaceLaunchMonitor: LaunchMonitoring {
    private let workspace: NSWorkspace
    private var observer: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func start(onLaunch: @escaping (LaunchedApp) -> Void) {
        stop()
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            onLaunch(app)
        }
    }

    func stop() {
        if let observer {
            workspace.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }
}
