import Foundation
import LocalAuthentication

/// Performs a single user authentication and reports success/failure.
/// Never throws to the caller — cancellation and errors are all "not authorized".
protocol Authenticating {
    func authenticate(reason: String) async -> Bool
}

/// Touch ID / Face ID with system-password fallback via `LocalAuthentication`.
///
/// A **fresh `LAContext` per attempt** is intentional: `LAContext` caches a
/// successful evaluation, so reusing one could let a later launch through
/// without a real prompt. `.deviceOwnerAuthentication` gives biometrics with an
/// automatic password fallback and requires no special entitlement.
final class LocalAuthenticator: Authenticating {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("NapLocker: auth unavailable: \(error?.localizedDescription ?? "unknown")")
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
