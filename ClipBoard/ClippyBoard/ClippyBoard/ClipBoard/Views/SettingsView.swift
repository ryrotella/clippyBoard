import SwiftUI
import SwiftData
import Carbon

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

            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
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
        .frame(width: 500, height: 420)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
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
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                if settings.appearanceMode == .highContrast {
                    Text("High Contrast mode increases visibility with stronger borders and colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Text Size")
                        Spacer()
                        Text("\(Int(settings.textSizeScale * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.textSizeScale, in: 0.8...1.5, step: 0.1)
                }

                Picker("Row Density", selection: $settings.rowDensityRaw) {
                    ForEach(RowDensity.allCases, id: \.rawValue) { density in
                        Text(density.displayName).tag(density.rawValue)
                    }
                }

                Picker("Thumbnail Size", selection: $settings.thumbnailSizeRaw) {
                    ForEach(ThumbnailSize.allCases, id: \.rawValue) { size in
                        Text(size.displayName).tag(size.rawValue)
                    }
                }

                Picker("Preview Lines", selection: $settings.maxPreviewLines) {
                    Text("1 line").tag(1)
                    Text("2 lines").tag(2)
                    Text("3 lines").tag(3)
                    Text("4 lines").tag(4)
                }
            } header: {
                Text("Layout")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Window Opacity")
                        Spacer()
                        Text("\(Int(settings.windowOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.windowOpacity, in: 0.5...1.0, step: 0.05)
                }

                HStack {
                    Text("Accent Color")
                    Spacer()
                    if settings.accentColorHex.isEmpty {
                        Text("System Default")
                            .foregroundStyle(.secondary)
                    }
                    ColorPicker("", selection: Binding(
                        get: { settings.accentColor ?? .accentColor },
                        set: { settings.accentColor = $0 }
                    ), supportsOpacity: false)
                    .labelsHidden()

                    if !settings.accentColorHex.isEmpty {
                        Button(action: { settings.accentColorHex = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to system default")
                    }
                }
            } header: {
                Text("Colors & Opacity")
            }

            Section {
                Toggle("Show Row Separators", isOn: $settings.showRowSeparators)

                if settings.showRowSeparators {
                    HStack {
                        Text("Separator Color")
                        Spacer()
                        if settings.separatorColorHex.isEmpty {
                            Text("Default")
                                .foregroundStyle(.secondary)
                        }
                        ColorPicker("", selection: Binding(
                            get: { settings.separatorColor ?? Color(nsColor: .separatorColor) },
                            set: { settings.separatorColor = $0 }
                        ), supportsOpacity: true)
                        .labelsHidden()

                        if !settings.separatorColorHex.isEmpty {
                            Button(action: { settings.separatorColorHex = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default")
                        }
                    }
                }
            } header: {
                Text("Row Separators")
            }

            Section {
                Toggle("Show Source App Icon", isOn: $settings.showSourceAppIcon)
                Toggle("Show Timestamps", isOn: $settings.showTimestamps)
                Toggle("Show Type Badges", isOn: $settings.showTypeBadges)
            } header: {
                Text("Display Elements")
            }

            Section {
                Button("Reset Appearance to Defaults") {
                    settings.resetAppearanceToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            Section {
                ShortcutRecorderRow(
                    label: "Toggle Clipboard",
                    shortcut: Binding(
                        get: { settings.popoverShortcut },
                        set: { settings.popoverShortcut = $0 }
                    )
                )

                ShortcutRecorderRow(
                    label: "Toggle Popout Window",
                    shortcut: Binding(
                        get: { settings.popoutShortcut },
                        set: { settings.popoutShortcut = $0 }
                    )
                )
            } header: {
                Text("Global Keyboard Shortcuts")
            } footer: {
                Text("Click the field and press your desired key combination. These shortcuts work system-wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset Shortcuts to Defaults") {
                    settings.resetShortcutsToDefaults()
                }
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
                Toggle("Sensitive Content Protection", isOn: $settings.sensitiveContentProtection)
                Text("Automatically detect passwords, API keys, and tokens. Require Touch ID or password to view or copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Security")
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
                .foregroundStyle(settings.accentColor ?? .accentColor)

            Text("ClippyBoard")
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
                    if let url = URL(string: "https://github.com/ryrotella/clippyBoard") {
                        NSWorkspace.shared.open(url)
                    }
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

// MARK: - Shortcut Recorder Row

struct ShortcutRecorderRow: View {
    let label: String
    @Binding var shortcut: KeyboardShortcut

    @State private var isRecording = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            Button(action: {
                isRecording = true
                isFocused = true
            }) {
                Text(isRecording ? "Press shortcut..." : shortcut.displayString)
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .onKeyPress { keyPress in
                guard isRecording else { return .ignored }

                // Convert SwiftUI key to Carbon key code
                if let keyCode = keyToKeyCode(keyPress.key),
                   !keyPress.modifiers.isEmpty {
                    let modifiers = modifiersToCarbon(keyPress.modifiers)
                    shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                    isRecording = false
                    isFocused = false
                    return .handled
                }

                return .ignored
            }
            .onChange(of: isFocused) { _, newValue in
                if !newValue {
                    isRecording = false
                }
            }

            if isRecording {
                Button(action: {
                    isRecording = false
                    isFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func keyToKeyCode(_ key: KeyEquivalent) -> UInt32? {
        // Convert to lowercase to handle Shift+Letter combinations
        let char = Character(key.character.lowercased())

        let keyMap: [Character: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
            "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
            "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19,
            "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
            "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
            " ": 0x31
        ]
        return keyMap[char]
    }

    private func modifiersToCarbon(_ modifiers: SwiftUI.EventModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
