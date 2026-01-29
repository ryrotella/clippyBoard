import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    @ObservedObject private var settings = AppSettings.shared

    @State private var showingClearConfirmation = false
    @State private var launchAtLogin = LaunchAtLoginService.shared.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginService.shared.isEnabled = newValue
                    }

                Picker("History Limit", selection: $settings.historyLimit) {
                    Text("100 items").tag(100)
                    Text("250 items").tag(250)
                    Text("500 items").tag(500)
                    Text("1000 items").tag(1000)
                    Text("Unlimited").tag(Int.max)
                }

                Picker("Default View", selection: $settings.defaultViewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue.capitalized, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
            } header: {
                Text("Behavior")
            }

            Section {
                HStack {
                    Text("Keyboard Shortcut")
                    Spacer()
                    Text(settings.globalShortcut)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                }
            } header: {
                Text("Shortcuts")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Privacy Tab

    private var privacyTab: some View {
        Form {
            Section {
                Toggle("Incognito Mode", isOn: $settings.incognitoMode)
                Text("When enabled, clipboard changes are not saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }

            Section {
                Picker("Auto-Clear History", selection: $settings.autoClearDays) {
                    Text("Never").tag(0)
                    Text("After 1 day").tag(1)
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                }
            } header: {
                Text("Data Retention")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded Apps")
                        .font(.headline)

                    Text("Clipboard content from these apps will not be saved (e.g., password managers).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // List excluded apps
                    ForEach(settings.excludedApps, id: \.self) { bundleId in
                        HStack {
                            Text(bundleId)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button(action: {
                                settings.excludedApps.removeAll { $0 == bundleId }
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                Button("Clear All History", role: .destructive) {
                    showingClearConfirmation = true
                }
                .alert("Clear Clipboard History?", isPresented: $showingClearConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        clipboardService.clearHistory(keepPinned: false)
                    }
                } message: {
                    Text("This will permanently delete all clipboard history, including pinned items.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clipboard")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("ClipBoard")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("A modern clipboard manager for macOS")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 20) {
                Button("Website") {
                    // TODO: Open website
                }

                Button("Support") {
                    // TODO: Open support
                }
            }
            .buttonStyle(.link)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(ClipboardService())
}
