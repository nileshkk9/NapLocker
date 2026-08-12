import Foundation
import ServiceManagement

/// Controls whether NapLocker starts automatically at login. Abstracted so the
/// UI can bind to it and tests can substitute a no-op double.
protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    /// True when `register()` succeeded but the user must still flip it on in
    /// System Settings → General → Login Items (common for apps not
    /// distributed via the Mac App Store).
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool)
}

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+). Registering the main
/// app is the modern, sandbox-friendly replacement for login-item shims.
final class LaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NapLocker: launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }
}
