import Foundation

/// The full persisted state of NapLocker: which apps are protected and the
/// global feature flags. Kept as one small value so a single load/save covers
/// everything the app needs to remember across launches.
struct PersistedState: Codable, Equatable {
    var apps: [ProtectedApp]
    var isEnabled: Bool

    static let empty = PersistedState(apps: [], isEnabled: true)
}

/// Abstraction over where protected-app state lives. `LockManager` depends on
/// this protocol (not a concrete file/UserDefaults), so tests can inject an
/// in-memory double. (Dependency Inversion.)
protocol LockListStore {
    func load() -> PersistedState
    func save(_ state: PersistedState)
}

/// Stores state as pretty-printed JSON at
/// `~/Library/Application Support/NapLocker/locked-apps.json`.
///
/// JSON (over `UserDefaults`) is deliberate: it is transparent, easy to inspect
/// or reset by hand, and trivial to unit-test.
final class JSONFileLockListStore: LockListStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("NapLocker", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("locked-apps.json")
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(_ state: PersistedState) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NapLocker: failed to save state: \(error.localizedDescription)")
        }
    }
}
