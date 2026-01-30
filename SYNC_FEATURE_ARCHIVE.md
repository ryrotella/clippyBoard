# Cross-Device Sync Feature Archive

> **Note:** This feature requires a **paid Apple Developer Program membership** ($99/year) to use CloudKit. Personal development teams don't support iCloud capabilities.

## Project Structure Diagram

```
ClipBoard/
├── ClippyBoard/
│   ├── ClippyBoard.entitlements    ← MODIFY (add CloudKit entitlements)
│   └── ClippyBoard/
│       └── ClipBoard/
│           ├── Models/
│           │   ├── ClipboardItem.swift    ← MODIFY (add sync properties)
│           │   ├── Pinboard.swift         ← MODIFY (add sync properties)
│           │   └── SyncSettings.swift     ← NEW FILE
│           ├── Views/
│           │   ├── ClipboardPopover.swift ← MODIFY (add sync badge)
│           │   ├── SettingsView.swift     ← MODIFY (add Sync tab)
│           │   └── SyncSettingsView.swift ← NEW FILE
│           ├── Services/
│           │   └── ClipboardService.swift ← MODIFY (sync-aware capture)
│           ├── Utilities/
│           │   ├── SyncConfiguration.swift      ← NEW FILE
│           │   ├── SensitiveContentDetector.swift ← NEW FILE
│           │   └── SyncMigration.swift          ← NEW FILE
│           └── AppDelegate.swift          ← MODIFY (CloudKit container)
```

---

## Prerequisites

Before implementing, you must:

1. **Join Apple Developer Program** ($99/year)
2. **In Xcode → Signing & Capabilities:**
   - Click "+" → Add "iCloud"
   - Check "CloudKit"
   - Add container: `iCloud.ryro.ClippyBoard`
   - Check "Key-value storage"

---

## File 1: ClippyBoard.entitlements

**Path:** `ClipBoard/ClippyBoard/ClippyBoard.entitlements`

**Action:** Replace entire contents

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.ryro.ClippyBoard</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
</dict>
</plist>
```

---

## File 2: ClipboardItem.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Models/ClipboardItem.swift`

**Action:** Replace entire file

```swift
import Foundation
import SwiftData
import AppKit
import CryptoKit

@Model
final class ClipboardItem {
    var id: UUID
    @Attribute(.externalStorage) var content: Data
    var textContent: String?
    var contentType: String // text, image, file, url
    var timestamp: Date
    var sourceApp: String? // Bundle ID
    var sourceAppName: String? // Display name
    var isPinned: Bool
    var pinboardId: UUID? // Which tab/pinboard
    var characterCount: Int?
    var searchableText: String

    // MARK: - Sync Properties
    var contentSize: Int64
    var contentHash: String?
    var isLocalOnly: Bool
    var deviceIdentifier: String?
    var lastModifiedDevice: String?
    var syncVersion: Int
    @Attribute(.externalStorage) var thumbnailData: Data?
    var isContentAvailable: Bool

    init(
        id: UUID = UUID(),
        content: Data,
        textContent: String? = nil,
        contentType: String,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceAppName: String? = nil,
        isPinned: Bool = false,
        pinboardId: UUID? = nil,
        characterCount: Int? = nil,
        searchableText: String = "",
        contentSize: Int64? = nil,
        contentHash: String? = nil,
        isLocalOnly: Bool = false,
        deviceIdentifier: String? = nil,
        lastModifiedDevice: String? = nil,
        syncVersion: Int = 1,
        thumbnailData: Data? = nil,
        isContentAvailable: Bool = true
    ) {
        self.id = id
        self.content = content
        self.textContent = textContent
        self.contentType = contentType
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
        self.pinboardId = pinboardId
        self.characterCount = characterCount
        self.searchableText = searchableText
        self.contentSize = contentSize ?? Int64(content.count)
        self.contentHash = contentHash ?? Self.computeHash(for: content)
        self.isLocalOnly = isLocalOnly
        self.deviceIdentifier = deviceIdentifier ?? DeviceIdentifier.current
        self.lastModifiedDevice = lastModifiedDevice ?? DeviceIdentifier.current
        self.syncVersion = syncVersion
        self.thumbnailData = thumbnailData
        self.isContentAvailable = isContentAvailable
    }

    // MARK: - Sync Helper Methods

    static var currentDeviceIdentifier: String {
        DeviceIdentifier.current
    }

    static func computeHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func generateThumbnail(from imageData: Data, maxSize: CGFloat = 100) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        // Calculate scale to fit within maxSize while preserving aspect ratio
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        // Create new image at thumbnail size
        let thumbnailImage = NSImage(size: newSize)
        thumbnailImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnailImage.unlockFocus()

        // Convert to JPEG at 50% compression
        guard let tiffData = thumbnailImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else {
            return nil
        }

        return jpegData
    }

    var contentTypeEnum: ContentType {
        ContentType(rawValue: contentType) ?? .text
    }

    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var displayText: String {
        if let text = textContent {
            return String(text.prefix(200))
        }
        return ""
    }

    var sourceAppIcon: NSImage? {
        guard let bundleId = sourceApp,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

enum ContentType: String, CaseIterable {
    case text = "text"
    case image = "image"
    case file = "file"
    case url = "url"

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "Link"
        }
    }

    var badgeColor: String {
        switch self {
        case .text: return "gray"
        case .image: return "purple"
        case .file: return "orange"
        case .url: return "blue"
        }
    }
}
```

---

## File 3: Pinboard.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Models/Pinboard.swift`

**Action:** Replace entire file

```swift
import Foundation
import SwiftData

@Model
final class Pinboard {
    var id: UUID
    var name: String // "Clipboard", "Useful Links", etc.
    var icon: String? // SF Symbol name
    var isDefault: Bool // "Clipboard" tab is default
    var sortOrder: Int

    // MARK: - Sync Properties
    var deviceIdentifier: String?
    var lastModifiedDevice: String?
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        deviceIdentifier: String? = nil,
        lastModifiedDevice: String? = nil,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.deviceIdentifier = deviceIdentifier ?? DeviceIdentifier.current
        self.lastModifiedDevice = lastModifiedDevice ?? DeviceIdentifier.current
        self.syncVersion = syncVersion
    }

    static func createDefault() -> Pinboard {
        Pinboard(
            name: "Clipboard",
            icon: "clipboard",
            isDefault: true,
            sortOrder: 0
        )
    }
}

// MARK: - Shared Device Identifier

enum DeviceIdentifier {
    static var current: String {
        if let identifier = UserDefaults.standard.string(forKey: "deviceIdentifier") {
            return identifier
        }
        let newIdentifier = Host.current().localizedName ?? UUID().uuidString
        UserDefaults.standard.set(newIdentifier, forKey: "deviceIdentifier")
        return newIdentifier
    }
}
```

---

## File 4: SyncConfiguration.swift (NEW)

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Utilities/SyncConfiguration.swift`

**Action:** Create new file

```swift
import Foundation
import SwiftData
import CloudKit

@MainActor
final class SyncConfiguration {
    static let shared = SyncConfiguration()

    private let containerIdentifier = "iCloud.ryro.ClippyBoard"

    private init() {}

    // MARK: - Container Creation

    func createSyncEnabledContainer() throws -> ModelContainer {
        let schema = Schema([
            ClipboardItem.self,
            Pinboard.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(containerIdentifier)
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func createLocalOnlyContainer() throws -> ModelContainer {
        let schema = Schema([
            ClipboardItem.self,
            Pinboard.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - CloudKit Availability

    func checkCloudKitAvailability() async -> CloudKitStatus {
        do {
            let container = CKContainer(identifier: containerIdentifier)
            let status = try await container.accountStatus()

            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .couldNotDetermine
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            print("SyncConfiguration: Failed to check CloudKit status: \(error)")
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - CloudKit Status

enum CloudKitStatus: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case error(String)

    var description: String {
        switch self {
        case .available:
            return "iCloud Available"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine:
            return "Unable to Determine"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isAvailable: Bool {
        self == .available
    }

    var icon: String {
        switch self {
        case .available:
            return "checkmark.icloud"
        case .noAccount:
            return "icloud.slash"
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            return "exclamationmark.icloud"
        case .error:
            return "xmark.icloud"
        }
    }
}
```

---

## File 5: SyncSettings.swift (NEW)

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Models/SyncSettings.swift`

**Action:** Create new file

```swift
import Foundation
import SwiftUI
import Combine

@MainActor
final class SyncSettings: ObservableObject {
    static let shared = SyncSettings()

    // MARK: - Local Settings (AppStorage)

    @AppStorage("syncEnabled") var syncEnabled: Bool = false {
        didSet {
            if syncEnabled {
                Task {
                    await checkCloudKitStatus()
                }
            }
        }
    }

    @AppStorage("syncImagesEnabled") var syncImagesEnabled: Bool = true
    @AppStorage("syncFilesEnabled") var syncFilesEnabled: Bool = true
    @AppStorage("maxSyncSizeMB") var maxSyncSizeMB: Int = 5

    // MARK: - Cloud-Synced Settings (NSUbiquitousKeyValueStore)

    private let kvStore = NSUbiquitousKeyValueStore.default

    var cloudSyncPreference: Bool {
        get { kvStore.bool(forKey: "syncPreference") }
        set {
            kvStore.set(newValue, forKey: "syncPreference")
            kvStore.synchronize()
        }
    }

    // MARK: - Published Status

    @Published var syncStatus: SyncStatus = .idle
    @Published var cloudKitStatus: CloudKitStatus = .couldNotDetermine
    @Published var lastSyncDate: Date?
    @Published var isSyncing: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        setupKVStoreObserver()
        Task {
            await checkCloudKitStatus()
        }
    }

    // MARK: - KV Store Sync

    private func setupKVStoreObserver() {
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleKVStoreChange(notification)
            }
            .store(in: &cancellables)

        // Start synchronization
        kvStore.synchronize()
    }

    private func handleKVStoreChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Settings changed from another device
            objectWillChange.send()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("SyncSettings: KV Store quota exceeded")
        case NSUbiquitousKeyValueStoreAccountChange:
            Task {
                await checkCloudKitStatus()
            }
        default:
            break
        }
    }

    // MARK: - CloudKit Status

    func checkCloudKitStatus() async {
        cloudKitStatus = await SyncConfiguration.shared.checkCloudKitAvailability()
    }

    // MARK: - Sync Decision Helpers

    func shouldSyncItem(_ item: ClipboardItem) -> Bool {
        guard syncEnabled else { return false }
        guard cloudKitStatus.isAvailable else { return false }

        // Check if marked local-only
        if item.isLocalOnly { return false }

        // Check content type
        switch item.contentTypeEnum {
        case .image:
            if !syncImagesEnabled { return false }
        case .file:
            if !syncFilesEnabled { return false }
        case .text, .url:
            break
        }

        // Check size limit
        let maxSizeBytes = Int64(maxSyncSizeMB) * 1024 * 1024
        if item.contentSize > maxSizeBytes {
            // Large items sync thumbnail only
            return item.thumbnailData != nil
        }

        return true
    }

    var maxSyncSizeBytes: Int64 {
        Int64(maxSyncSizeMB) * 1024 * 1024
    }
}

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }
}
```

---

## File 6: SensitiveContentDetector.swift (NEW)

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Utilities/SensitiveContentDetector.swift`

**Action:** Create new file

```swift
import Foundation

enum SensitiveContentDetector {

    // MARK: - Sensitive Patterns

    private static let sensitivePatterns: [(name: String, pattern: String)] = [
        ("Credit Card", #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#),
        ("SSN", #"\b\d{3}-\d{2}-\d{4}\b"#),
        ("API Key", #"(?i)(api[_-]?key|apikey)[=:]\s*['\"]?[\w-]{20,}"#),
        ("Private Key", #"-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"#),
        ("Bearer Token", #"(?i)bearer\s+[\w-]+\.[\w-]+\.[\w-]+"#),
        ("Password Field", #"(?i)(password|passwd|pwd)[=:]\s*['\"]?.{4,}"#),
        ("Secret Key", #"(?i)(secret[_-]?key|secretkey)[=:]\s*['\"]?[\w-]{10,}"#),
        ("AWS Key", #"(?i)(aws[_-]?access[_-]?key|aws[_-]?secret)[=:]\s*['\"]?[\w/+]{20,}"#),
        ("GitHub Token", #"gh[ps]_[A-Za-z0-9_]{36,}"#),
        ("Generic Token", #"(?i)(token|auth)[=:]\s*['\"]?[\w-]{20,}"#)
    ]

    // MARK: - Password Manager Bundle IDs

    private static let passwordManagerBundleIds: Set<String> = [
        // 1Password
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        "com.agilebits.onepassword-ios",

        // LastPass
        "com.lastpass.LastPass",
        "com.lastpass.lpios",

        // Bitwarden
        "com.bitwarden.desktop",
        "com.bitwarden.ios",

        // Dashlane
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.Dashlane",

        // Keeper
        "com.callpod.keeper",
        "com.keepersecurity.keeper",

        // Enpass
        "io.enpass.mac",
        "io.enpass.Enpass",

        // RoboForm
        "com.siber.roboform",
        "com.siber.RoboForm",

        // NordPass
        "com.nordpass.macos",
        "com.nordpass.NordPass",

        // Keychain Access (macOS)
        "com.apple.keychainaccess"
    ]

    // MARK: - Detection Methods

    static func containsSensitiveContent(_ text: String) -> Bool {
        for (_, pattern) in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    static func detectSensitiveContentTypes(_ text: String) -> [String] {
        var detected: [String] = []
        for (name, pattern) in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                detected.append(name)
            }
        }
        return detected
    }

    static func isPasswordManager(_ bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return passwordManagerBundleIds.contains(bundleId)
    }

    // MARK: - Combined Check

    static func shouldMarkLocalOnly(text: String?, sourceApp: String?) -> Bool {
        // Check if from password manager
        if isPasswordManager(sourceApp) {
            return true
        }

        // Check text content for sensitive patterns
        if let text = text, containsSensitiveContent(text) {
            return true
        }

        return false
    }
}
```

---

## File 7: SyncMigration.swift (NEW)

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Utilities/SyncMigration.swift`

**Action:** Create new file

```swift
import Foundation
import SwiftData

@MainActor
enum SyncMigration {

    private static let migrationKey = "syncMigrationCompleted_v1"

    static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    // MARK: - Migration Entry Point

    static func migrateExistingData(in container: ModelContainer) async {
        guard !hasMigrated else {
            print("SyncMigration: Already migrated")
            return
        }

        print("SyncMigration: Starting migration of existing data...")

        let context = container.mainContext

        do {
            // Migrate ClipboardItems
            let itemDescriptor = FetchDescriptor<ClipboardItem>()
            let items = try context.fetch(itemDescriptor)

            var migratedItems = 0
            for item in items {
                if migrateClipboardItem(item) {
                    migratedItems += 1
                }
            }
            print("SyncMigration: Migrated \(migratedItems) clipboard items")

            // Migrate Pinboards
            let pinboardDescriptor = FetchDescriptor<Pinboard>()
            let pinboards = try context.fetch(pinboardDescriptor)

            var migratedPinboards = 0
            for pinboard in pinboards {
                if migratePinboard(pinboard) {
                    migratedPinboards += 1
                }
            }
            print("SyncMigration: Migrated \(migratedPinboards) pinboards")

            // Save changes
            try context.save()

            // Mark migration complete
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("SyncMigration: Migration completed successfully")

        } catch {
            print("SyncMigration: Migration failed: \(error)")
        }
    }

    // MARK: - Item Migration

    private static func migrateClipboardItem(_ item: ClipboardItem) -> Bool {
        var changed = false

        // Set content size if not set
        if item.contentSize == 0 {
            item.contentSize = Int64(item.content.count)
            changed = true
        }

        // Compute hash if not set
        if item.contentHash == nil || item.contentHash?.isEmpty == true {
            item.contentHash = ClipboardItem.computeHash(for: item.content)
            changed = true
        }

        // Set device identifier if not set
        if item.deviceIdentifier == nil || item.deviceIdentifier?.isEmpty == true {
            item.deviceIdentifier = DeviceIdentifier.current
            changed = true
        }

        // Set last modified device if not set
        if item.lastModifiedDevice == nil || item.lastModifiedDevice?.isEmpty == true {
            item.lastModifiedDevice = DeviceIdentifier.current
            changed = true
        }

        // Generate thumbnail for large images
        if item.contentTypeEnum == .image {
            let maxSyncSize = SyncSettings.shared.maxSyncSizeBytes

            if item.contentSize > maxSyncSize && item.thumbnailData == nil {
                item.thumbnailData = ClipboardItem.generateThumbnail(from: item.content)
                changed = true
            }
        }

        // Check for sensitive content and mark as local-only
        if let textContent = item.textContent {
            if SensitiveContentDetector.containsSensitiveContent(textContent) {
                item.isLocalOnly = true
                changed = true
            }
        }

        // Check if from password manager
        if SensitiveContentDetector.isPasswordManager(item.sourceApp) {
            item.isLocalOnly = true
            changed = true
        }

        return changed
    }

    private static func migratePinboard(_ pinboard: Pinboard) -> Bool {
        var changed = false

        // Set device identifier if not set
        if pinboard.deviceIdentifier == nil || pinboard.deviceIdentifier?.isEmpty == true {
            pinboard.deviceIdentifier = DeviceIdentifier.current
            changed = true
        }

        // Set last modified device if not set
        if pinboard.lastModifiedDevice == nil || pinboard.lastModifiedDevice?.isEmpty == true {
            pinboard.lastModifiedDevice = DeviceIdentifier.current
            changed = true
        }

        return changed
    }

    // MARK: - Reset Migration (for debugging)

    static func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        print("SyncMigration: Migration flag reset")
    }
}
```

---

## File 8: SyncSettingsView.swift (NEW)

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Views/SyncSettingsView.swift`

**Action:** Create new file

```swift
import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject private var syncSettings = SyncSettings.shared

    @State private var isCheckingStatus = false

    var body: some View {
        Form {
            // iCloud Status Section
            Section {
                HStack {
                    Image(systemName: syncSettings.cloudKitStatus.icon)
                        .foregroundStyle(syncSettings.cloudKitStatus.isAvailable ? .green : .orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Status")
                            .font(.headline)
                        Text(syncSettings.cloudKitStatus.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isCheckingStatus {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Refresh") {
                            checkStatus()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("Account")
            }

            // Sync Enable Section
            Section {
                Toggle("Enable iCloud Sync", isOn: $syncSettings.syncEnabled)
                    .disabled(!syncSettings.cloudKitStatus.isAvailable)

                if syncSettings.syncEnabled {
                    HStack {
                        Image(systemName: syncSettings.syncStatus.icon)
                            .foregroundStyle(syncSettings.syncStatus.color)
                        Text(syncSettings.syncStatus.description)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let lastSync = syncSettings.lastSyncDate {
                            Text("Last: \(lastSync.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                if !syncSettings.cloudKitStatus.isAvailable {
                    Text("Sign in to iCloud in System Settings to enable sync.")
                } else {
                    Text("Syncs clipboard history across your Mac devices signed into the same iCloud account.")
                }
            }

            // Content Settings Section
            if syncSettings.syncEnabled {
                Section {
                    Toggle("Sync Images", isOn: $syncSettings.syncImagesEnabled)
                    Toggle("Sync Files", isOn: $syncSettings.syncFilesEnabled)

                    Picker("Max Item Size", selection: $syncSettings.maxSyncSizeMB) {
                        Text("1 MB").tag(1)
                        Text("5 MB").tag(5)
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                    }
                } header: {
                    Text("Content")
                } footer: {
                    Text("Items larger than the max size will sync thumbnails only. Full content stays on the original device.")
                }

                // Privacy Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.blue)
                            Text("Privacy Protection")
                                .font(.headline)
                        }

                        Text("The following content is automatically excluded from sync:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            privacyItem("Credit card numbers")
                            privacyItem("Social Security numbers")
                            privacyItem("API keys and tokens")
                            privacyItem("Private keys")
                            privacyItem("Password manager content")
                        }
                        .padding(.leading, 8)
                    }
                } header: {
                    Text("Privacy")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkStatus()
        }
    }

    private func privacyItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkStatus() {
        isCheckingStatus = true
        Task {
            await syncSettings.checkCloudKitStatus()
            isCheckingStatus = false
        }
    }
}

// MARK: - Preview

#Preview {
    SyncSettingsView()
        .frame(width: 450, height: 500)
}
```

---

## File 9: AppDelegate.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/AppDelegate.swift`

**Action:** Replace the imports and class up through `setupModelContainer()` and add sync observer

```swift
import AppKit
import SwiftUI
import SwiftData
import Carbon
import CoreData

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var clipboardService: ClipboardService!
    private var screenshotService: ScreenshotService!
    private var modelContainer: ModelContainer!
    private var hotKeyRef: EventHotKeyRef?
    private var popoutHotKeyRef: EventHotKeyRef?
    private var popoutWindowController: PopoutBoardWindowController?
    private var syncEventObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize model container
        setupModelContainer()

        // Initialize clipboard service
        clipboardService = ClipboardService()
        clipboardService.setModelContainer(modelContainer)
        clipboardService.startMonitoring()

        // Initialize screenshot service
        screenshotService = ScreenshotService()
        screenshotService.setModelContainer(modelContainer)
        screenshotService.onScreenshotCaptured = { [weak self] in
            self?.clipboardService.refreshItems()
            self?.triggerCaptureAnimation()
        }
        screenshotService.startMonitoring()

        // Setup status bar item
        setupStatusItem()

        // Setup popover
        setupPopover()

        // Setup global hotkeys
        setupHotkeys()

        // Observe capture events to animate icon
        setupCaptureObserver()

        // Setup sync event observer
        setupSyncObserver()

        // Observe hotkey notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopover),
            name: .toggleClipboardPopover,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopoutBoard),
            name: .togglePopoutBoard,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPopoutBoard),
            name: .openPopoutBoard,
            object: nil
        )

        // Run sync migration if needed
        if SyncSettings.shared.syncEnabled {
            Task {
                await SyncMigration.migrateExistingData(in: modelContainer)
            }
        }
    }

    private func setupModelContainer() {
        // Try to create sync-enabled container if sync is enabled
        if SyncSettings.shared.syncEnabled {
            do {
                modelContainer = try SyncConfiguration.shared.createSyncEnabledContainer()
                print("AppDelegate: Created CloudKit-enabled container")
                ensureDefaultPinboard()
                return
            } catch {
                print("AppDelegate: Failed to create CloudKit container, falling back to local: \(error)")
            }
        }

        // Fallback to local-only container
        do {
            modelContainer = try SyncConfiguration.shared.createLocalOnlyContainer()
            print("AppDelegate: Created local-only container")
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        ensureDefaultPinboard()
    }

    private func ensureDefaultPinboard() {
        // Ensure default pinboard exists
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Pinboard>(
            predicate: #Predicate { $0.isDefault == true }
        )

        do {
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                let defaultPinboard = Pinboard.createDefault()
                context.insert(defaultPinboard)
                try context.save()
            }
        } catch {
            print("Failed to ensure default pinboard: \(error)")
        }
    }

    // MARK: - Sync Observer

    private func setupSyncObserver() {
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSyncEvent(notification)
        }
    }

    @objc private func handleSyncEvent(_ notification: Notification) {
        print("AppDelegate: Received sync event")

        // Update sync status
        SyncSettings.shared.syncStatus = .syncing

        // Refresh items after sync
        clipboardService.refreshItems()

        // Mark as synced after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            SyncSettings.shared.syncStatus = .synced
            SyncSettings.shared.lastSyncDate = Date()
        }
    }

    // ... rest of AppDelegate remains the same ...
```

---

## File 10: ClipboardService.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Services/ClipboardService.swift`

**Action:** Replace `captureClipboard()` method and add `setLocalOnly()` at the end

```swift
    private func captureClipboard() {
        guard let modelContainer = modelContainer else {
            print("ClipboardService: No model container set")
            return
        }

        let modelContext = modelContainer.mainContext
        let pasteboard = NSPasteboard.general

        // Get active app info
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check if app is excluded
        if AppSettings.shared.isAppExcluded(sourceApp) {
            return
        }

        // Check incognito mode
        if AppSettings.shared.incognitoMode {
            return
        }

        // Check if from password manager - mark as local only
        let isFromPasswordManager = SensitiveContentDetector.isPasswordManager(sourceApp)

        // Determine content type and extract content
        // Check order matters: files first, then images, then URLs, then text

        // 1. Check for files (copied from Finder)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            print("ClipboardService: Found \(fileURLs.count) file(s)")

            let filePaths = fileURLs.map { $0.path }
            let fileNames = fileURLs.map { $0.lastPathComponent }
            let displayText = fileNames.joined(separator: ", ")
            let searchText = fileNames.joined(separator: " ").lowercased()

            let item = ClipboardItem(
                content: filePaths.joined(separator: "\n").data(using: .utf8) ?? Data(),
                textContent: displayText,
                contentType: ContentType.file.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: displayText.count,
                searchableText: "file " + searchText,
                isLocalOnly: isFromPasswordManager
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 2. Check for images
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            print("ClipboardService: Found image data")

            // Generate thumbnail for large images
            let maxSyncSize = SyncSettings.shared.maxSyncSizeBytes
            var thumbnail: Data? = nil

            if imageData.count > maxSyncSize {
                thumbnail = ClipboardItem.generateThumbnail(from: imageData)
                print("ClipboardService: Generated thumbnail for large image")
            }

            let item = ClipboardItem(
                content: imageData,
                contentType: ContentType.image.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                searchableText: "image",
                isLocalOnly: isFromPasswordManager,
                thumbnailData: thumbnail
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 3. Check for URLs (web links, not file URLs)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL],
           let url = urls.first,
           !url.isFileURL {
            print("ClipboardService: Found URL: \(url)")

            let urlString = url.absoluteString

            // Check for sensitive content in URL
            let hasSensitiveContent = SensitiveContentDetector.containsSensitiveContent(urlString)

            let item = ClipboardItem(
                content: urlString.data(using: .utf8) ?? Data(),
                textContent: urlString,
                contentType: ContentType.url.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: urlString.count,
                searchableText: urlString.lowercased(),
                isLocalOnly: isFromPasswordManager || hasSensitiveContent
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 4. Check for text (last, as other types may also have text representations)
        if let string = pasteboard.string(forType: .string) {
            print("ClipboardService: Found text content: \(string.prefix(50))...")

            // Check for sensitive content
            let hasSensitiveContent = SensitiveContentDetector.containsSensitiveContent(string)
            let shouldBeLocalOnly = isFromPasswordManager || hasSensitiveContent

            if hasSensitiveContent {
                print("ClipboardService: Detected sensitive content, marking as local-only")
            }

            let contentType = detectContentType(for: string)
            print("ClipboardService: Creating ClipboardItem with type: \(contentType)")
            let item = ClipboardItem(
                content: string.data(using: .utf8) ?? Data(),
                textContent: string,
                contentType: contentType.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: string.count,
                searchableText: string.lowercased(),
                isLocalOnly: shouldBeLocalOnly
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
        }
    }

    // ... existing methods ...

    // MARK: - Sync Control

    func setLocalOnly(_ item: ClipboardItem, localOnly: Bool) {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext
        item.isLocalOnly = localOnly
        item.lastModifiedDevice = DeviceIdentifier.current
        item.syncVersion += 1
        try? context.save()
        refreshItems()
    }
```

---

## File 11: SettingsView.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Views/SettingsView.swift`

**Action:** Add Sync tab to TabView

```swift
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            syncTab
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
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
        .frame(width: 450, height: 400)
    }

    // MARK: - Sync Tab

    private var syncTab: some View {
        SyncSettingsView()
    }
```

---

## File 12: ClipboardPopover.swift

**Path:** `ClipBoard/ClippyBoard/ClippyBoard/ClipBoard/Views/ClipboardPopover.swift`

**Action:** Update footer and add SyncStatusBadge

Replace `footerView` and add `SyncStatusBadge` struct at the end:

```swift
    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Sync status badge
            if SyncSettings.shared.syncEnabled {
                SyncStatusBadge()
            }

            if AppSettings.shared.incognitoMode {
                Label("Incognito", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Clear") {
                clipboardService.clearHistory()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Sync Status Badge

struct SyncStatusBadge: View {
    @ObservedObject private var syncSettings = SyncSettings.shared

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: syncSettings.syncStatus.icon)
                .font(.caption)
                .foregroundStyle(syncSettings.syncStatus.color)
                .rotationEffect(.degrees(syncSettings.syncStatus == .syncing && isAnimating ? 360 : 0))
                .animation(
                    syncSettings.syncStatus == .syncing
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: isAnimating
                )

            if syncSettings.syncStatus == .syncing {
                Text("Syncing")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .onAppear {
            isAnimating = syncSettings.syncStatus == .syncing
        }
        .onChange(of: syncSettings.syncStatus) { _, newStatus in
            isAnimating = newStatus == .syncing
        }
    }
}
```

---

## Implementation Checklist

When you're ready to implement (after getting paid Apple Developer account):

- [ ] Join Apple Developer Program ($99/year)
- [ ] Update `ClippyBoard.entitlements` (File 1)
- [ ] Enable iCloud capability in Xcode
- [ ] Create new file: `SyncConfiguration.swift` (File 4)
- [ ] Create new file: `SyncSettings.swift` (File 5)
- [ ] Create new file: `SensitiveContentDetector.swift` (File 6)
- [ ] Create new file: `SyncMigration.swift` (File 7)
- [ ] Create new file: `SyncSettingsView.swift` (File 8)
- [ ] Update `ClipboardItem.swift` (File 2)
- [ ] Update `Pinboard.swift` (File 3)
- [ ] Update `AppDelegate.swift` (File 9)
- [ ] Update `ClipboardService.swift` (File 10)
- [ ] Update `SettingsView.swift` (File 11)
- [ ] Update `ClipboardPopover.swift` (File 12)
- [ ] Add new files to Xcode project
- [ ] Build and test

---

## Testing Checklist

- [ ] Enable sync in Settings → Sync tab
- [ ] Copy text on Mac A, verify appears on Mac B
- [ ] Copy small image, verify syncs
- [ ] Copy large image (>5MB), verify thumbnail syncs
- [ ] Copy "password: secret123", verify marked local-only
- [ ] Copy from 1Password, verify not synced
- [ ] Pin an item, verify syncs
- [ ] Create pinboard, verify syncs
- [ ] Edit same item on two Macs offline, go online, verify last-write-wins
- [ ] Make changes offline, verify syncs when back online
- [ ] Disable sync, verify local changes don't sync
