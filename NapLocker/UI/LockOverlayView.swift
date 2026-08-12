import SwiftUI

/// The opaque cover shown over a protected app while it is being unlocked.
/// While authenticating it simply hides the app; if authentication is cancelled
/// or fails it offers Unlock (retry) and Quit App.
struct LockOverlayView: View {
    @ObservedObject var model: OverlayViewModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(model.appName)
                    .font(.title2.weight(.semibold))

                switch model.state {
                case .authenticating:
                    Text("Authenticate to continue")
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)

                case .failed:
                    Text("Authentication required")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Quit App", role: .destructive) { model.onQuit() }
                        Button("Unlock") { model.onUnlock() }
                            .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.large)
                }
            }
            .padding(40)
        }
    }
}
