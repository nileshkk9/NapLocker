import XCTest
@testable import NapLocker

@MainActor
final class LockManagerTests: XCTestCase {

    // MARK: - Doubles

    struct StubApp: LaunchedApp {
        var bundleIdentifier: String?
        var localizedName: String?
    }

    final class MockStore: LockListStore {
        var state: PersistedState
        private(set) var saveCount = 0
        init(_ state: PersistedState) { self.state = state }
        func load() -> PersistedState { state }
        func save(_ state: PersistedState) { self.state = state; saveCount += 1 }
    }

    final class MockMonitor: LaunchMonitoring {
        private var handler: ((LaunchedApp) -> Void)?
        func start(onLaunch: @escaping (LaunchedApp) -> Void) { handler = onLaunch }
        func stop() { handler = nil }
        func fire(_ app: LaunchedApp) { handler?(app) }
    }

    final class MockAuthenticator: Authenticating {
        var result = true
        private(set) var callCount = 0
        func authenticate(reason: String) async -> Bool {
            callCount += 1
            return result
        }
    }

    final class MockTerminator: AppTerminating {
        private(set) var terminated: [String] = []
        func terminate(_ app: LaunchedApp) {
            terminated.append(app.bundleIdentifier ?? "")
        }
    }

    final class MockLaunchAtLogin: LaunchAtLoginControlling {
        var enabled = false
        var requiresApproval = false
        var isEnabled: Bool { enabled }
        func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    }

    @MainActor
    final class MockOverlay: OverlayPresenting {
        private(set) var presentCount = 0
        private(set) var presentedName: String?
        private(set) var states: [OverlayState] = []
        private(set) var dismissCount = 0
        var onUnlock: (() -> Void)?
        var onQuit: (() -> Void)?

        private var waiters: [(check: () -> Bool, cont: CheckedContinuation<Void, Never>)] = []

        func present(appName: String, onUnlock: @escaping () -> Void, onQuit: @escaping () -> Void) {
            presentCount += 1
            presentedName = appName
            self.onUnlock = onUnlock
            self.onQuit = onQuit
            signal()
        }
        func setState(_ state: OverlayState) { states.append(state); signal() }
        func dismiss() { dismissCount += 1; signal() }

        var didFail: Bool { states.contains { if case .failed = $0 { return true } else { return false } } }

        /// Suspends until `predicate` holds, re-checked on every overlay event.
        func waitUntil(_ predicate: @escaping () -> Bool) async {
            if predicate() { return }
            await withCheckedContinuation { cont in
                waiters.append((predicate, cont))
            }
        }

        private func signal() {
            waiters.removeAll { waiter in
                if waiter.check() { waiter.cont.resume(); return true }
                return false
            }
        }
    }

    // MARK: - Fixtures

    private let appA = ProtectedApp(bundleId: "com.test.a", name: "A")

    private func makeManager(
        state: PersistedState,
        store: MockStore? = nil,
        monitor: MockMonitor = MockMonitor(),
        auth: MockAuthenticator = MockAuthenticator(),
        terminator: MockTerminator = MockTerminator(),
        overlay: MockOverlay? = nil,
        login: MockLaunchAtLogin = MockLaunchAtLogin()
    ) -> (LockManager, MockStore, MockMonitor, MockAuthenticator, MockTerminator, MockOverlay) {
        let realStore = store ?? MockStore(state)
        let overlay = overlay ?? MockOverlay()
        let manager = LockManager(
            store: realStore,
            monitor: monitor,
            authenticator: auth,
            terminator: terminator,
            overlay: overlay,
            launchAtLogin: login
        )
        manager.start()
        return (manager, realStore, monitor, auth, terminator, overlay)
    }

    // MARK: - Tests

    func testProtectedLaunchPresentsOverlayAndUnlocksOnSuccess() async {
        let (_, _, monitor, auth, terminator, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true))

        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        await overlay.waitUntil { overlay.dismissCount == 1 }

        XCTAssertEqual(overlay.presentCount, 1)
        XCTAssertEqual(overlay.presentedName, "A")
        XCTAssertEqual(auth.callCount, 1)
        XCTAssertEqual(overlay.dismissCount, 1)
        XCTAssertTrue(terminator.terminated.isEmpty)
    }

    func testAuthFailureKeepsOverlayWithoutTerminating() async {
        let auth = MockAuthenticator(); auth.result = false
        let (_, _, monitor, _, terminator, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        await overlay.waitUntil { overlay.didFail }

        XCTAssertTrue(overlay.didFail)
        XCTAssertEqual(overlay.dismissCount, 0)
        XCTAssertTrue(terminator.terminated.isEmpty)
    }

    func testQuitTerminatesAndDismisses() async {
        let auth = MockAuthenticator(); auth.result = false
        let (_, _, monitor, _, terminator, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        await overlay.waitUntil { overlay.didFail }

        overlay.onQuit?()

        XCTAssertEqual(terminator.terminated, [appA.bundleId])
        XCTAssertEqual(overlay.dismissCount, 1)
    }

    func testUnlockRetrySucceeds() async {
        let auth = MockAuthenticator(); auth.result = false
        let (_, _, monitor, _, _, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        await overlay.waitUntil { overlay.didFail }

        auth.result = true
        overlay.onUnlock?()
        await overlay.waitUntil { overlay.dismissCount == 1 }

        XCTAssertEqual(auth.callCount, 2)
        XCTAssertEqual(overlay.dismissCount, 1)
    }

    func testRapidRelaunchIsDeduped() async {
        let (_, _, monitor, auth, _, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true))

        // Both fires happen before the async auth of the first can resolve.
        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))
        await overlay.waitUntil { overlay.dismissCount == 1 }

        XCTAssertEqual(overlay.presentCount, 1)
        XCTAssertEqual(auth.callCount, 1)
    }

    func testNonProtectedLaunchIgnored() {
        let (_, _, monitor, auth, _, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true))

        monitor.fire(StubApp(bundleIdentifier: "com.other.app", localizedName: "Other"))

        XCTAssertEqual(overlay.presentCount, 0)
        XCTAssertEqual(auth.callCount, 0)
    }

    func testDisabledIgnoresLaunch() {
        let (_, _, monitor, auth, _, overlay) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: false))

        monitor.fire(StubApp(bundleIdentifier: appA.bundleId, localizedName: "A"))

        XCTAssertEqual(overlay.presentCount, 0)
        XCTAssertEqual(auth.callCount, 0)
    }

    func testAddAndRemovePersist() async {
        let (manager, store, _, _, _, _) =
            makeManager(state: PersistedState(apps: [], isEnabled: true))

        let before = store.saveCount
        manager.add(appA)
        XCTAssertTrue(manager.isProtected(bundleId: appA.bundleId))
        XCTAssertEqual(store.state.apps, [appA])
        XCTAssertGreaterThan(store.saveCount, before)

        await manager.remove(appA)
        XCTAssertFalse(manager.isProtected(bundleId: appA.bundleId))
        XCTAssertTrue(store.state.apps.isEmpty)
    }

    func testRemoveRequiresAuthAndFailsSafelyWhenAuthFails() async {
        let auth = MockAuthenticator(); auth.result = false
        let (manager, store, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        await manager.remove(appA)

        XCTAssertEqual(auth.callCount, 1)
        XCTAssertTrue(manager.isProtected(bundleId: appA.bundleId))
        XCTAssertEqual(store.state.apps, [appA])
    }

    func testTogglingEnabledPersists() async {
        let (manager, store, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true))

        await manager.setEnabled(false)
        XCTAssertFalse(store.state.isEnabled)
    }

    func testEnablingProtectionDoesNotRequireAuth() async {
        let auth = MockAuthenticator()
        let (manager, store, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: false), auth: auth)

        await manager.setEnabled(true)

        XCTAssertEqual(auth.callCount, 0)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(store.state.isEnabled)
    }

    func testDisablingProtectionRequiresAuthAndFailsSafelyWhenAuthFails() async {
        let auth = MockAuthenticator(); auth.result = false
        let (manager, store, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        await manager.setEnabled(false)

        XCTAssertEqual(auth.callCount, 1)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(store.state.isEnabled)
    }

    func testQuitRequiresAuthWhenProtectionEnabled() async {
        let auth = MockAuthenticator(); auth.result = false
        let (manager, _, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: true), auth: auth)

        let allowed = await manager.requestQuit()

        XCTAssertEqual(auth.callCount, 1)
        XCTAssertFalse(allowed)
    }

    func testQuitAllowedWithoutAuthWhenProtectionDisabled() async {
        let auth = MockAuthenticator()
        let (manager, _, _, _, _, _) =
            makeManager(state: PersistedState(apps: [appA], isEnabled: false), auth: auth)

        let allowed = await manager.requestQuit()

        XCTAssertEqual(auth.callCount, 0)
        XCTAssertTrue(allowed)
    }

    func testLaunchAtLoginRequiresApprovalIsSurfaced() {
        let login = MockLaunchAtLogin()
        login.requiresApproval = true
        let (manager, _, _, _, _, _) =
            makeManager(state: PersistedState(apps: [], isEnabled: true), login: login)

        XCTAssertTrue(manager.launchAtLoginRequiresApproval)
    }
}
