import AppKit
import Observation

/// The application's brain. Observes launches and, for protected apps, covers
/// the screen and requires authentication before letting the app be used.
///
/// It depends only on protocols (`LockListStore`, `LaunchMonitoring`,
/// `Authenticating`, `AppTerminating`, `OverlayPresenting`,
/// `LaunchAtLoginControlling`), so the entire flow is unit-testable with doubles
/// and carries no hard dependency on AppKit or biometrics. (Dependency Inversion.)
@MainActor
@Observable
final class LockManager {
    private(set) var apps: [ProtectedApp]
    private(set) var isEnabled: Bool

    /// Mirrors `launchAtLogin.isEnabled`/`.requiresApproval` in a stored,
    /// Observation-tracked property. A computed property reading straight from
    /// `SMAppService` would never trigger a SwiftUI re-render, since Observation
    /// only tracks stored properties it owns.
    private(set) var isLaunchAtLoginEnabled: Bool
    private(set) var launchAtLoginRequiresApproval: Bool

    /// Bundle identifiers currently mid-unlock, to dedupe rapid relaunches.
    @ObservationIgnored private var inFlight: Set<String> = []

    @ObservationIgnored private let store: LockListStore
    @ObservationIgnored private let monitor: LaunchMonitoring
    @ObservationIgnored private let authenticator: Authenticating
    @ObservationIgnored private let terminator: AppTerminating
    @ObservationIgnored private let overlay: OverlayPresenting
    @ObservationIgnored private let launchAtLogin: LaunchAtLoginControlling
    @ObservationIgnored private let ownBundleId = Bundle.main.bundleIdentifier

    init(
        store: LockListStore,
        monitor: LaunchMonitoring,
        authenticator: Authenticating,
        terminator: AppTerminating,
        overlay: OverlayPresenting,
        launchAtLogin: LaunchAtLoginControlling
    ) {
        self.store = store
        self.monitor = monitor
        self.authenticator = authenticator
        self.terminator = terminator
        self.overlay = overlay
        self.launchAtLogin = launchAtLogin

        let state = store.load()
        self.apps = state.apps
        self.isEnabled = state.isEnabled
        self.isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        self.launchAtLoginRequiresApproval = launchAtLogin.requiresApproval
    }

    /// Start observing launches. Call once, after construction.
    func start() {
        monitor.start { [weak self] app in
            self?.handleLaunch(app)
        }
    }

    // MARK: - Protected-app management

    func add(_ app: ProtectedApp) {
        guard !apps.contains(app) else { return }
        apps.append(app)
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    /// Removing a protected app weakens protection, so it requires the same
    /// authentication as unlocking one — otherwise anyone with menu-bar access
    /// could remove an app from the list and relaunch it freely.
    func remove(_ app: ProtectedApp) async {
        guard await authenticator.authenticate(reason: "remove \(app.name) from Protected Apps") else { return }
        apps.removeAll { $0 == app }
        persist()
    }

    func isProtected(bundleId: String) -> Bool {
        apps.contains { $0.bundleId == bundleId }
    }

    /// Turning protection ON is always allowed. Turning it OFF requires
    /// authentication — otherwise the toggle itself is a bypass for the whole
    /// app.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            isEnabled = true
            persist()
            return
        }
        guard await authenticator.authenticate(reason: "disable protection") else { return }
        isEnabled = false
        persist()
    }

    /// Quitting NapLocker while protection is enabled is itself a bypass — it
    /// would let someone sidestep every locked app at once by killing the
    /// watcher instead of unlocking. Gate it the same way as disabling
    /// protection. When protection is already off there is nothing to bypass,
    /// so quitting needs no extra prompt.
    ///
    /// This only covers the graceful menu path; Force Quit / `kill -9` /
    /// Activity Monitor can still end the process outright. Closing that gap
    /// needs a separate watchdog process and is out of scope for v1 (see
    /// README limitations).
    func requestQuit() async -> Bool {
        guard isEnabled else { return true }
        return await authenticator.authenticate(reason: "quit NapLocker")
    }

    // MARK: - Launch at login (source of truth is the system)

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
        refreshLaunchAtLoginState()
    }

    /// Re-reads login-item status from the system. Call when the menu is
    /// opened, since the user may have changed it from System Settings
    /// directly, or approval may have completed there since our last read.
    func refreshLaunchAtLoginState() {
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        launchAtLoginRequiresApproval = launchAtLogin.requiresApproval
    }

    // MARK: - Core flow

    private func handleLaunch(_ app: LaunchedApp) {
        guard isEnabled else { return }
        guard let bundleId = app.bundleIdentifier,
              bundleId != ownBundleId,
              isProtected(bundleId: bundleId),
              !inFlight.contains(bundleId) else { return }

        inFlight.insert(bundleId)

        overlay.present(
            appName: app.localizedName ?? "This app",
            onUnlock: { [weak self] in self?.attempt(app, bundleId: bundleId) },
            onQuit: { [weak self] in self?.quit(app, bundleId: bundleId) }
        )
        attempt(app, bundleId: bundleId)
    }

    private func attempt(_ app: LaunchedApp, bundleId: String) {
        overlay.setState(.authenticating)
        let name = app.localizedName ?? "this app"
        Task { @MainActor in
            let ok = await authenticator.authenticate(reason: "unlock \(name)")
            if ok {
                overlay.dismiss()
                inFlight.remove(bundleId)
            } else {
                overlay.setState(.failed)
            }
        }
    }

    private func quit(_ app: LaunchedApp, bundleId: String) {
        terminator.terminate(app)
        overlay.dismiss()
        inFlight.remove(bundleId)
    }

    // MARK: - Persistence

    private func persist() {
        store.save(PersistedState(apps: apps, isEnabled: isEnabled))
    }
}
