import SwiftUI
import SwiftData
import Carbon

struct SettingsView: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var apiServer = LocalAPIServer.shared
    @ObservedObject private var bookmarkManager = SecurityScopedBookmarkManager.shared

    @State private var showingClearConfirmation = false
    @State private var launchAtLogin = LaunchAtLoginService.shared.isEnabled
    @State private var showingTokenCopied = false
    @State private var showingInstructionsCopied = false
    @State private var showingDocsExported = false

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

            advancedTab
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 480)
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

            Section {
                Picker("Window Mode", selection: $settings.panelMode) {
                    ForEach(PanelMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }

                if settings.panelModeSetting == .slidingPanel {
                    Picker("Panel Edge", selection: $settings.panelEdge) {
                        ForEach(PanelEdge.allCases, id: \.rawValue) { edge in
                            Text(edge.displayName).tag(edge.rawValue)
                        }
                    }

                    Toggle("Keep Panel on Top", isOn: $settings.panelAlwaysOnTop)
                }
            } header: {
                Text("Window Style")
            } footer: {
                if settings.panelModeSetting == .slidingPanel && !settings.panelAlwaysOnTop {
                    Text("Panel can be overlapped by other windows. Click menu bar icon to bring it back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sliding Panel slides from screen edge. Classic Popover appears from menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Click-to-Paste", isOn: $settings.clickToPaste)

                if !permissionService.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Requires Accessibility permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant") {
                            permissionService.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Paste Behavior")
            } footer: {
                Text("When enabled, clicking an item pastes it directly. Otherwise, it only copies to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Copy Feedback Toast", isOn: $settings.copyFeedbackToast)
                Toggle("Play Sound on Copy", isOn: $settings.copyFeedbackSound)
            } header: {
                Text("Feedback")
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
                Toggle("Show Copy Button", isOn: $settings.showCopyButton)
                Toggle("Simplified Display", isOn: $settings.simplifiedDisplay)
            } header: {
                Text("Display Elements")
            } footer: {
                if settings.simplifiedDisplay {
                    Text("Simplified mode hides type badges and shows minimal information.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Toggle("Quick Access Shortcuts", isOn: $settings.quickAccessShortcutsEnabled)

                if settings.quickAccessShortcutsEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(1...5, id: \.self) { index in
                            HStack {
                                Text("⌥\(index)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text("Paste item #\(index)")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Quick Access")
            } footer: {
                Text("Use ⌥1 through ⌥5 to instantly paste recent items.")
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
                Toggle("Detect Private Browsing", isOn: $settings.privateBrowsingDetection)
                Text("Automatically detect incognito/private browsing windows in Safari, Chrome, Firefox, Edge, Brave, and other browsers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.privateBrowsingDetection {
                    Picker("When Detected", selection: $settings.privateBrowsingAction) {
                        Text("Don't save").tag("skip")
                        Text("Mark as sensitive").tag("sensitive")
                    }
                    .pickerStyle(.segmented)

                    Text(settings.privateBrowsingAction == "skip"
                         ? "Clipboard content from private windows will not be saved."
                         : "Clipboard content from private windows will be saved but marked as sensitive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Private Browsing")
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

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section {
                Toggle("Enable Local API", isOn: $settings.apiEnabled)
                    .onChange(of: settings.apiEnabled) { _, newValue in
                        if newValue {
                            LocalAPIServer.shared.start()
                        } else {
                            LocalAPIServer.shared.stop()
                        }
                    }

                if settings.apiEnabled {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $settings.apiPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(apiServer.isRunning ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(apiServer.isRunning ? "Running" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                        if !apiServer.isRunning {
                            Button("Start") {
                                apiServer.start()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Restart") {
                                apiServer.stop()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    apiServer.start()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if let token = apiServer.currentToken {
                        HStack {
                            Text("API Token")
                            Spacer()
                            Text(token.prefix(8) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                                showingTokenCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showingTokenCopied = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if showingTokenCopied {
                            Text("Token copied!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Button("Regenerate Token") {
                        apiServer.regenerateToken()
                    }
                    .foregroundStyle(.red)

                    Divider()

                    HStack {
                        Button("Copy Agent Instructions") {
                            copyAgentInstructions()
                        }
                        .buttonStyle(.bordered)

                        Button("Export API Docs") {
                            exportAPIDocs()
                        }
                        .buttonStyle(.bordered)
                    }

                    if showingInstructionsCopied {
                        Text("Agent instructions copied to clipboard!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if showingDocsExported {
                        Text("API documentation exported!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Agent API")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local HTTP API for agents and automation tools.")
                    Text("Use \"Copy Agent Instructions\" to share with AI assistants.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if permissionService.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") {
                            permissionService.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility enables click-to-paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Screenshots Folder")
                    Spacer()
                    if bookmarkManager.hasScreenshotsFolderAccess,
                       let url = bookmarkManager.screenshotsFolderURL {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                        Button("Change") {
                            bookmarkManager.selectScreenshotsFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Select Folder") {
                            bookmarkManager.selectScreenshotsFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if bookmarkManager.hasScreenshotsFolderAccess {
                    Button("Remove Folder Access", role: .destructive) {
                        bookmarkManager.clearScreenshotsFolder()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Screenshot History")
            } footer: {
                if bookmarkManager.hasScreenshotsFolderAccess {
                    Text("Screenshots saved to the selected folder will be captured automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select your Screenshots folder to enable automatic screenshot history. Usually this is your Desktop or a Screenshots folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Show Onboarding Again") {
                    settings.onboardingCompleted = false
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }

                Button("Reset All Settings") {
                    settings.resetAppearanceToDefaults()
                    settings.resetShortcutsToDefaults()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Reset")
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

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("A modern clipboard manager for macOS")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 20) {
                Button("Github") {
                    if let url = URL(string: "https://github.com/ryrotella/clippyBoard") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Made by Ryan Rotella") {
                    if let url = URL(string: "https://rotella.tech") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .buttonStyle(.link)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Agent API Helpers

    private func copyAgentInstructions() {
        guard let token = apiServer.currentToken else { return }
        let port = settings.apiPort

        let instructions = """
        # ClippyBoard API Access

        You have access to my ClippyBoard clipboard manager API running locally.

        **Connection Details:**
        - Base URL: `http://localhost:\(port)`
        - Token: `\(token)`

        **Authentication:**
        Include this header in all requests:
        ```
        Authorization: Bearer \(token)
        ```

        **Available Endpoints:**

        | Method | Endpoint | Description |
        |--------|----------|-------------|
        | GET | /api/health | Health check |
        | GET | /api/items | List all clipboard items |
        | GET | /api/items/{id} | Get specific item |
        | POST | /api/items | Create item (`{"content": "text", "type": "text"}`) |
        | DELETE | /api/items/{id} | Delete item |
        | PUT | /api/items/{id}/pin | Toggle pin |
        | POST | /api/items/{id}/copy | Copy to clipboard |
        | POST | /api/items/{id}/paste | Copy and paste to active window |
        | POST | /api/paste | Paste current clipboard |
        | GET | /api/screenshots | List screenshots |
        | GET | /api/screenshots/{id}/image | Get screenshot image |
        | GET | /api/search?q={query} | Search items |

        **Example:**
        ```bash
        curl -H "Authorization: Bearer \(token)" http://localhost:\(port)/api/items
        ```
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instructions, forType: .string)
        showingInstructionsCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingInstructionsCopied = false
        }
    }

    private func exportAPIDocs() {
        let docs = """
        # ClippyBoard API Documentation

        ClippyBoard provides a local HTTP API for agents and automation tools.

        ## Server Configuration

        - **Default Port:** \(settings.apiPort)
        - **Binding:** localhost only (127.0.0.1)
        - **Max Request Size:** 1MB
        - **Rate Limiting:** 60 connections per minute per IP

        ## Authentication

        All endpoints require a Bearer token in the Authorization header:

        ```
        Authorization: Bearer <your-token>
        ```

        Get your token from: Settings → Advanced → Agent API → Copy Token

        ## Endpoints

        ### Health Check

        ```
        GET /api/health
        ```

        **Response:**
        ```json
        {"status": "ok", "version": "1.2"}
        ```

        ---

        ### List All Clipboard Items

        ```
        GET /api/items
        ```

        **Response:**
        ```json
        {
          "items": [
            {
              "id": "<UUID>",
              "type": "text|url|image",
              "text": "preview text",
              "timestamp": "2024-01-15T10:30:00Z",
              "sourceApp": "Application Name",
              "isPinned": false,
              "characterCount": 42
            }
          ]
        }
        ```

        ---

        ### Get Specific Item

        ```
        GET /api/items/{id}
        ```

        **Response:**
        ```json
        {
          "id": "<UUID>",
          "type": "text|url|image",
          "content": "full content",
          "timestamp": "2024-01-15T10:30:00Z",
          "sourceApp": "Application Name",
          "isPinned": false
        }
        ```

        ---

        ### Create Clipboard Item

        ```
        POST /api/items
        Content-Type: application/json

        {
          "content": "the text content",
          "type": "text|url",
          "sourceApp": "optional app identifier",
          "isPinned": false
        }
        ```

        **Response:**
        ```json
        {
          "id": "<UUID>",
          "type": "text",
          "timestamp": "2024-01-15T10:30:00Z",
          "message": "Item created successfully"
        }
        ```

        ---

        ### Delete Item

        ```
        DELETE /api/items/{id}
        ```

        **Response:**
        ```json
        {"message": "Item deleted successfully"}
        ```

        ---

        ### Toggle Pin

        ```
        PUT /api/items/{id}/pin
        ```

        **Response:**
        ```json
        {
          "id": "<UUID>",
          "isPinned": true,
          "message": "Item pinned"
        }
        ```

        ---

        ### Copy to Clipboard

        ```
        POST /api/items/{id}/copy
        ```

        **Response:**
        ```json
        {"message": "Item copied to clipboard"}
        ```

        ---

        ### Copy and Paste to Active Window

        ```
        POST /api/items/{id}/paste
        ```

        Requires Accessibility permissions.

        **Response:**
        ```json
        {
          "message": "Item pasted successfully",
          "pasteSimulated": true
        }
        ```

        ---

        ### Paste Current Clipboard

        ```
        POST /api/paste
        ```

        Requires Accessibility permissions.

        **Response:**
        ```json
        {
          "message": "Paste simulated successfully",
          "pasteSimulated": true
        }
        ```

        ---

        ### List Screenshots

        ```
        GET /api/screenshots
        ```

        **Response:**
        ```json
        {
          "screenshots": [
            {
              "id": "<UUID>",
              "timestamp": "2024-01-15T10:30:00Z",
              "sourceApp": "Screenshot"
            }
          ]
        }
        ```

        ---

        ### Get Screenshot Image

        ```
        GET /api/screenshots/{id}/image
        ```

        **Response:** Binary image data with appropriate Content-Type header.

        ---

        ### Search Items

        ```
        GET /api/search?q={query}
        ```

        **Response:**
        ```json
        {
          "query": "search term",
          "count": 5,
          "items": [...]
        }
        ```

        ---

        ## Error Responses

        All errors return JSON:

        ```json
        {"error": "Error message"}
        ```

        **Status Codes:**
        - `400` - Bad request or invalid parameters
        - `401` - Unauthorized (invalid/missing token)
        - `404` - Resource not found
        - `429` - Rate limit exceeded
        - `500` - Server error

        ---

        ## Example Usage with curl

        ```bash
        # Set your token
        TOKEN="your-token-here"
        PORT=\(settings.apiPort)

        # Health check
        curl -H "Authorization: Bearer $TOKEN" http://localhost:$PORT/api/health

        # Get all items
        curl -H "Authorization: Bearer $TOKEN" http://localhost:$PORT/api/items

        # Create an item
        curl -X POST http://localhost:$PORT/api/items \\
          -H "Authorization: Bearer $TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{"content": "Hello World", "type": "text"}'

        # Search
        curl -H "Authorization: Bearer $TOKEN" "http://localhost:$PORT/api/search?q=hello"

        # Paste an item to active window
        curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost:$PORT/api/items/{id}/paste
        ```
        """

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "ClippyBoard-API-Docs.md"
        savePanel.title = "Export API Documentation"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try docs.write(to: url, atomically: true, encoding: .utf8)
                showingDocsExported = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingDocsExported = false
                }
            } catch {
                print("Failed to export docs: \(error)")
            }
        }
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
