import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The menu bar popover: the entire UI surface of NapLocker. Deliberately
/// minimal — the protected list, add/remove, two toggles, and Quit.
struct MenuContentView: View {
    @Bindable var manager: LockManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protected Apps")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            if manager.apps.isEmpty {
                Text("No apps protected yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(manager.apps) { app in
                    HStack {
                        Text(app.name)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            Task { await manager.remove(app) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(app.name)")
                    }
                    .padding(.horizontal, 12)
                }
            }

            Button {
                addApp()
            } label: {
                Label("Add App…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Divider()

            Toggle("Protection Enabled", isOn: enabledBinding)
                .padding(.horizontal, 12)

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .padding(.horizontal, 12)

            if manager.launchAtLoginRequiresApproval {
                Button {
                    openLoginItemsSettings()
                } label: {
                    Text("Approve in System Settings…")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }

            Divider()

            Button("Quit NapLocker") {
                Task {
                    if await manager.requestQuit() {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 260)
        .onAppear {
            manager.refreshLaunchAtLoginState()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { manager.isEnabled },
            set: { newValue in Task { await manager.setEnabled(newValue) } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { manager.isLaunchAtLoginEnabled },
            set: { manager.setLaunchAtLogin($0) }
        )
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Presents an open panel scoped to applications and resolves the chosen
    /// `.app` bundle to a `ProtectedApp`.
    ///
    /// NapLocker runs as an accessory app (no Dock icon), so it isn't
    /// guaranteed to be the frontmost/active app when the menu bar popover is
    /// tapped. Without an explicit activation, the panel can appear without
    /// key focus, making its first click(s) silently miss. Activating first,
    /// and presenting the panel on the next run-loop turn (after the popover
    /// has finished closing), makes selection reliable.
    private func addApp() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.prompt = "Protect"

            guard panel.runModal() == .OK, let url = panel.url,
                  let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return }

            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            manager.add(ProtectedApp(bundleId: bundleId, name: name))
        }
    }
}
