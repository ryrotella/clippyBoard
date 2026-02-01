# ClipBoard Mobile App Companion Specification

> Reference document for building the iOS companion app to ClipBoard macOS clipboard manager.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Models](#data-models)
4. [Features Matrix](#features-matrix)
5. [Settings & Customization](#settings--customization)
6. [Design Tokens](#design-tokens)
7. [UI Components](#ui-components)
8. [Sync Strategy](#sync-strategy)
9. [Platform Considerations](#platform-considerations)
10. [API Reference](#api-reference)

---

## Overview

### macOS App Summary

**ClipBoard** is a modern clipboard manager for macOS that:
- Monitors system clipboard for changes
- Stores clipboard history (text, images, URLs, files)
- Captures screenshots automatically
- Provides quick access via menu bar popover or floating window
- Supports pinning, searching, filtering, and text transformations
- Offers extensive appearance customization

### Mobile App Goals

The iOS companion app should:
- Sync clipboard history with the macOS app
- Allow viewing, searching, and copying items
- Push clipboard items to/from macOS
- Provide a native iOS experience while maintaining feature parity where applicable

---

## Architecture

### macOS App Structure

```
ClipBoard/
├── ClipBoardApp.swift          # @main App entry, Settings scene
├── AppDelegate.swift           # Menu bar, hotkeys, services setup
├── Models/
│   ├── AppSettings.swift       # User preferences (AppStorage)
│   ├── ClipboardItem.swift     # SwiftData model
│   └── Pinboard.swift          # Pinboard collections (future)
├── Views/
│   ├── ClipboardPopover.swift  # Menu bar popover UI
│   ├── PopoutBoardView.swift   # Floating window UI
│   ├── ClipboardItemRow.swift  # Item row component
│   ├── ImagePreviewView.swift  # Image preview modal
│   └── SettingsView.swift      # Settings tabs
├── Services/
│   ├── ClipboardService.swift  # Clipboard monitoring & management
│   ├── ScreenshotService.swift # Screenshot capture monitoring
│   └── LaunchAtLoginService.swift
└── Utilities/
    ├── DesignTokens.swift      # Sizing constants
    └── TextTransformations.swift
```

### Recommended iOS Structure

```
ClipBoardMobile/
├── ClipBoardMobileApp.swift
├── Models/
│   ├── AppSettings.swift       # Shared settings (use same keys)
│   ├── ClipboardItem.swift     # Identical model for sync
│   └── SyncManager.swift       # iCloud/CloudKit sync
├── Views/
│   ├── ContentView.swift       # Main list view
│   ├── ClipboardItemRow.swift  # Adapted row component
│   ├── ItemDetailView.swift    # Full item view
│   ├── SearchView.swift        # Search interface
│   └── SettingsView.swift      # iOS settings
├── Services/
│   ├── ClipboardService.swift  # iOS clipboard (limited)
│   └── SyncService.swift       # Sync with macOS
└── Utilities/
    ├── DesignTokens.swift      # Shared tokens
    └── TextTransformations.swift
```

---

## Data Models

### ClipboardItem (SwiftData)

```swift
import SwiftData
import Foundation

@Model
final class ClipboardItem {
    // MARK: - Identifiers
    var id: UUID = UUID()
    var timestamp: Date = Date()

    // MARK: - Content
    var content: Data                    // Raw content bytes
    var textContent: String?             // Text representation (for search)
    var contentType: String              // "text", "image", "url", "file"

    // MARK: - Metadata
    var sourceApp: String?               // Bundle ID of source app
    var sourceAppName: String?           // Display name of source app
    var isPinned: Bool = false
    var characterCount: Int?             // For text items
    var searchableText: String = ""      // Lowercase text for search

    // MARK: - Sync
    var syncID: String?                  // CloudKit record ID
    var lastModified: Date = Date()
    var isDeleted: Bool = false          // Soft delete for sync

    // MARK: - Computed Properties
    var contentTypeEnum: ContentType {
        ContentType(rawValue: contentType) ?? .text
    }

    var displayText: String {
        if let text = textContent {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(500)
                .description
        }
        return ""
    }

    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

enum ContentType: String, CaseIterable {
    case text = "text"
    case image = "image"
    case url = "url"
    case file = "file"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }
}
```

### Pinboard (Future Feature)

```swift
@Model
final class Pinboard {
    var id: UUID = UUID()
    var name: String
    var icon: String = "folder"
    var color: String = "#007AFF"
    var isDefault: Bool = false
    var items: [ClipboardItem] = []
    var sortOrder: Int = 0

    static func createDefault() -> Pinboard {
        let board = Pinboard(name: "Default")
        board.isDefault = true
        return board
    }
}
```

---

## Features Matrix

| Feature | macOS | iOS | Notes |
|---------|-------|-----|-------|
| **Clipboard Monitoring** | ✅ Auto | ⚠️ Manual | iOS doesn't allow background clipboard access |
| **Screenshot Capture** | ✅ Auto | ❌ | Not possible on iOS |
| **View History** | ✅ | ✅ | Core feature |
| **Search** | ✅ | ✅ | Full-text search |
| **Filter by Type** | ✅ | ✅ | text/image/url/file |
| **Copy to Clipboard** | ✅ | ✅ | |
| **Pin Items** | ✅ | ✅ | |
| **Delete Items** | ✅ | ✅ | |
| **Image Preview** | ✅ | ✅ | |
| **Text Transformations** | ✅ | ✅ | |
| **Appearance Themes** | ✅ | ✅ | System/Light/Dark/HighContrast |
| **Text Size** | ✅ | ✅ | Use Dynamic Type on iOS |
| **Custom Accent Color** | ✅ | ✅ | |
| **Keyboard Shortcuts** | ✅ | ❌ | N/A on iOS |
| **Menu Bar** | ✅ | ❌ | N/A on iOS |
| **Widgets** | ❌ | ✅ | Add iOS widgets |
| **Share Extension** | ❌ | ✅ | Capture from share sheet |
| **iCloud Sync** | 🔮 | 🔮 | Future feature |

### iOS-Specific Features to Add

1. **Share Extension** - Capture content from other apps via share sheet
2. **Widgets** - Quick access to recent/pinned items
3. **Shortcuts Integration** - Siri Shortcuts for common actions
4. **Haptic Feedback** - For copy/delete actions
5. **Pull to Refresh** - Sync with macOS
6. **Swipe Actions** - Pin/delete on swipe

---

## Settings & Customization

### AppSettings Keys (Use Same Keys for Sync)

```swift
// MARK: - General
@AppStorage("historyLimit") var historyLimit: Int = 500
@AppStorage("incognitoMode") var incognitoMode: Bool = false
@AppStorage("autoClearDays") var autoClearDays: Int = 0

// MARK: - Appearance
@AppStorage("appearanceMode") var appearanceModeRaw: String = "system"
@AppStorage("textSizeScale") var textSizeScale: Double = 1.0
@AppStorage("accentColorHex") var accentColorHex: String = ""
@AppStorage("rowDensity") var rowDensityRaw: String = "comfortable"
@AppStorage("thumbnailSize") var thumbnailSizeRaw: String = "medium"
@AppStorage("showRowSeparators") var showRowSeparators: Bool = true
@AppStorage("separatorColorHex") var separatorColorHex: String = ""
@AppStorage("showSourceAppIcon") var showSourceAppIcon: Bool = true
@AppStorage("showTimestamps") var showTimestamps: Bool = true
@AppStorage("showTypeBadges") var showTypeBadges: Bool = true
@AppStorage("maxPreviewLines") var maxPreviewLines: Int = 2

// MARK: - iOS Specific
@AppStorage("enableHaptics") var enableHaptics: Bool = true
@AppStorage("enableWidgets") var enableWidgets: Bool = true
@AppStorage("syncEnabled") var syncEnabled: Bool = false
```

### Appearance Mode Enum

```swift
enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case highContrast = "highContrast"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .highContrast: return .dark
        }
    }
}
```

### Row Density Enum

```swift
enum RowDensity: String, CaseIterable {
    case compact = "compact"
    case comfortable = "comfortable"
    case spacious = "spacious"

    var displayName: String { rawValue.capitalized }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 8
        case .spacious: return 12
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 10
        case .spacious: return 14
        }
    }
}
```

### Thumbnail Size Enum

```swift
enum ThumbnailSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String { rawValue.capitalized }

    var smallSize: CGFloat {
        switch self {
        case .small: return 28
        case .medium: return 36
        case .large: return 48
        }
    }

    var largeSize: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 60
        case .large: return 80
        }
    }
}
```

---

## Design Tokens

### Typography

```swift
enum DesignTokens {
    // Font Sizes (base values, scale with Dynamic Type)
    static let badgeFont: CGFloat = 9
    static let bodyFont: CGFloat = 12
    static let captionFont: CGFloat = 11

    // Icon Sizes
    static let iconSize: CGFloat = 16
    static let largeIconSize: CGFloat = 20

    // Thumbnail Sizes
    static let smallThumbnail: CGFloat = 36
    static let largeThumbnail: CGFloat = 60

    // Spacing
    static let rowPaddingCompact: CGFloat = 4
    static let rowPaddingComfortable: CGFloat = 8
    static let rowPaddingSpacious: CGFloat = 12

    // Corner Radius
    static let badgeRadius: CGFloat = 4
    static let cardRadius: CGFloat = 8
    static let buttonRadius: CGFloat = 6
}
```

### Colors

```swift
// Content Type Badge Colors
extension ContentType {
    var badgeColor: Color {
        switch self {
        case .text: return .gray
        case .image: return .purple
        case .file: return .orange
        case .url: return .blue
        }
    }
}

// Color Hex Extension (for custom colors)
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components,
              components.count >= 3 else { return nil }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

---

## UI Components

### ClipboardItemRow (iOS Adaptation)

```swift
struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject private var settings = AppSettings.shared

    // Use Dynamic Type with custom scaling
    @ScaledMetric(relativeTo: .caption2) private var baseBadgeFont = DesignTokens.badgeFont
    @ScaledMetric(relativeTo: .body) private var baseBodyFont = DesignTokens.bodyFont

    private var badgeFont: CGFloat { baseBadgeFont * settings.textSizeScale }
    private var bodyFont: CGFloat { baseBodyFont * settings.textSizeScale }

    var body: some View {
        HStack(spacing: settings.rowDensity.spacing) {
            // Thumbnail
            contentPreview
                .frame(width: thumbnailSize, height: thumbnailSize)

            VStack(alignment: .leading, spacing: 2) {
                // Header row
                HStack(spacing: 6) {
                    if settings.showTypeBadges {
                        TypeBadge(type: item.contentTypeEnum, fontSize: badgeFont)
                    }

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(settings.accentColor ?? .orange)
                    }

                    Spacer()

                    if settings.showTimestamps {
                        Text(item.relativeTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Content preview
                if item.contentTypeEnum != .image {
                    Text(item.displayText.isEmpty ? "(No text)" : item.displayText)
                        .font(.system(size: bodyFont))
                        .lineLimit(settings.maxPreviewLines)
                }

                // Source app
                if settings.showSourceAppIcon, let appName = item.sourceAppName {
                    Text(appName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical: settings.rowDensity.verticalPadding)
    }
}
```

### Filter Chips

```swift
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        AppSettings.shared.accentColor ?? .accentColor
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? accentColor.opacity(0.5) : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
```

### Type Badge

```swift
struct TypeBadge: View {
    let type: ContentType
    let fontSize: CGFloat

    var body: some View {
        Text(type.displayName)
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(type.badgeColor.opacity(0.15))
            .foregroundStyle(type.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
```

---

## Sync Strategy

### Option 1: iCloud + CloudKit (Recommended)

```swift
// Use CloudKit for syncing ClipboardItem records
// Pros: Native Apple integration, automatic conflict resolution
// Cons: Requires iCloud account, limited to Apple ecosystem

class SyncService {
    private let container = CKContainer(identifier: "iCloud.com.yourname.ClipBoard")
    private let database: CKDatabase

    init() {
        database = container.privateCloudDatabase
    }

    func syncItem(_ item: ClipboardItem) async throws {
        let record = CKRecord(recordType: "ClipboardItem")
        record["id"] = item.id.uuidString
        record["timestamp"] = item.timestamp
        record["contentType"] = item.contentType
        record["textContent"] = item.textContent
        record["isPinned"] = item.isPinned

        // Store content as CKAsset for large data
        if let url = saveContentToTempFile(item.content) {
            record["content"] = CKAsset(fileURL: url)
        }

        try await database.save(record)
    }

    func fetchChanges() async throws -> [ClipboardItem] {
        // Fetch changes since last sync token
        // ...
    }
}
```

### Option 2: Local Network Sync

```swift
// Direct sync over local network using Bonjour/MultipeerConnectivity
// Pros: Works without internet, faster
// Cons: Devices must be on same network

class LocalSyncService {
    private let serviceType = "clipboard-sync"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    func startAdvertising() { /* ... */ }
    func startBrowsing() { /* ... */ }
    func sendItem(_ item: ClipboardItem, to peer: MCPeerID) { /* ... */ }
}
```

### Sync Data Format

```swift
struct SyncPayload: Codable {
    let version: Int = 1
    let timestamp: Date
    let deviceID: String
    let items: [SyncItem]

    struct SyncItem: Codable {
        let id: UUID
        let timestamp: Date
        let contentType: String
        let textContent: String?
        let contentBase64: String?  // For images/files
        let isPinned: Bool
        let isDeleted: Bool
        let lastModified: Date
    }
}
```

---

## Platform Considerations

### iOS Clipboard Limitations

```swift
// iOS clipboard access is limited:
// - Can only read when app is in foreground
// - No background monitoring
// - UIPasteboard.general for access

class iOSClipboardService {
    private let pasteboard = UIPasteboard.general

    // Call this when app becomes active
    func checkForNewContent() -> ClipboardItem? {
        if pasteboard.hasStrings, let string = pasteboard.string {
            return createItem(text: string)
        }
        if pasteboard.hasImages, let image = pasteboard.image {
            return createItem(image: image)
        }
        if pasteboard.hasURLs, let url = pasteboard.url {
            return createItem(url: url)
        }
        return nil
    }

    func copyToClipboard(_ item: ClipboardItem) {
        switch item.contentTypeEnum {
        case .text, .url:
            pasteboard.string = item.textContent
        case .image:
            if let image = UIImage(data: item.content) {
                pasteboard.image = image
            }
        case .file:
            // Handle file data
            pasteboard.setData(item.content, forPasteboardType: "public.data")
        }

        // Haptic feedback
        if AppSettings.shared.enableHaptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
```

### Share Extension

```swift
// ShareExtension/ShareViewController.swift
class ShareViewController: SLComposeServiceViewController {
    override func didSelectPost() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            return
        }

        // Handle different content types
        if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
            attachment.loadItem(forTypeIdentifier: "public.plain-text") { data, error in
                if let text = data as? String {
                    self.saveToClipboardHistory(text: text)
                }
            }
        }
        // Handle images, URLs, etc.
    }

    private func saveToClipboardHistory(text: String) {
        // Save to shared App Group container
        // MainApp will pick it up on next launch
    }
}
```

### Widget Extension

```swift
// WidgetExtension/ClipboardWidget.swift
struct ClipboardWidget: Widget {
    let kind: String = "ClipboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ClipboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Clips")
        .description("Quick access to recent clipboard items.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClipboardWidgetView: View {
    let entry: ClipboardEntry

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(entry.items.prefix(3)) { item in
                HStack {
                    Image(systemName: item.contentTypeEnum.icon)
                    Text(item.displayText)
                        .lineLimit(1)
                }
            }
        }
        .padding()
    }
}
```

---

## API Reference

### Text Transformations

```swift
enum TextTransformation: String, CaseIterable {
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case capitalize = "Capitalize"
    case trimWhitespace = "Trim Whitespace"
    case removeLineBreaks = "Remove Line Breaks"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"
    case base64Encode = "Base64 Encode"
    case base64Decode = "Base64 Decode"
    case countCharacters = "Count Characters"
    case countWords = "Count Words"

    var icon: String {
        switch self {
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .capitalize: return "textformat"
        case .trimWhitespace: return "scissors"
        case .removeLineBreaks: return "text.alignleft"
        case .urlEncode, .urlDecode: return "link"
        case .base64Encode, .base64Decode: return "doc.text"
        case .countCharacters, .countWords: return "number"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalize: return text.capitalized
        case .trimWhitespace: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeLineBreaks: return text.replacingOccurrences(of: "\n", with: " ")
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .urlDecode: return text.removingPercentEncoding ?? text
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            if let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
            return text
        case .countCharacters: return "Characters: \(text.count)"
        case .countWords: return "Words: \(text.split(separator: " ").count)"
        }
    }
}
```

### Notification Names

```swift
extension Notification.Name {
    // Sync
    static let syncDidComplete = Notification.Name("syncDidComplete")
    static let syncDidFail = Notification.Name("syncDidFail")

    // Clipboard
    static let clipboardDidChange = Notification.Name("clipboardDidChange")
    static let itemDidPin = Notification.Name("itemDidPin")
    static let itemDidDelete = Notification.Name("itemDidDelete")

    // Settings
    static let settingsDidChange = Notification.Name("settingsDidChange")
}
```

---

## Implementation Checklist

### Phase 1: Core Features
- [ ] Project setup with SwiftUI + SwiftData
- [ ] ClipboardItem model (matching macOS)
- [ ] AppSettings with shared keys
- [ ] Main list view with items
- [ ] Search functionality
- [ ] Filter chips
- [ ] Copy to clipboard
- [ ] Item detail view

### Phase 2: Customization
- [ ] Appearance modes (system/light/dark/high contrast)
- [ ] Text size scaling
- [ ] Row density options
- [ ] Thumbnail sizes
- [ ] Custom accent color
- [ ] Row separators with custom color
- [ ] Display element toggles

### Phase 3: iOS Features
- [ ] Share extension
- [ ] Widget extension
- [ ] Haptic feedback
- [ ] Swipe actions (pin/delete)
- [ ] Pull to refresh
- [ ] App lifecycle clipboard check

### Phase 4: Sync
- [ ] App Group for shared data
- [ ] CloudKit integration
- [ ] Sync conflict resolution
- [ ] Background sync
- [ ] Sync status indicator

### Phase 5: Polish
- [ ] Onboarding flow
- [ ] Empty states
- [ ] Error handling
- [ ] Accessibility audit
- [ ] Performance optimization
- [ ] App Store assets

---

## Resources

- [macOS Source Code](/Users/ryanrotella/ClipBoardApp/ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [App Extensions Guide](https://developer.apple.com/app-extensions/)
- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)

---

*Generated from ClipBoard macOS v1.0.0 - January 2026*
