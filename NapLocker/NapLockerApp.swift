import SwiftUI

@main
struct NapLockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NapLocker", systemImage: "lock.fill") {
            MenuContentView(manager: appDelegate.lockManager)
        }
        .menuBarExtraStyle(.window)
    }
}
