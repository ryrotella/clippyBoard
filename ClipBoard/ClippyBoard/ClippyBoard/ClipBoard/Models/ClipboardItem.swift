import Foundation
import SwiftData
import AppKit

@Model
final class ClipboardItem {
    var id: UUID
    var content: Data
    var textContent: String?
    var contentType: String // text, image, file, url
    var timestamp: Date
    var sourceApp: String? // Bundle ID
    var sourceAppName: String? // Display name
    var isPinned: Bool
    var pinboardId: UUID? // Which tab/pinboard
    var characterCount: Int?
    var searchableText: String

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
        searchableText: String = ""
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
