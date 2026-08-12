import Foundation

/// A single app the user has chosen to protect, identified by its bundle identifier.
///
/// Identity is the `bundleId` alone — the display `name` is cosmetic. This keeps
/// matching against a freshly launched process trivial and stable across renames.
struct ProtectedApp: Codable, Identifiable, Hashable {
    let bundleId: String
    let name: String

    var id: String { bundleId }

    static func == (lhs: ProtectedApp, rhs: ProtectedApp) -> Bool {
        lhs.bundleId == rhs.bundleId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
    }
}
