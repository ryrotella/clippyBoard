import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers
import SwiftUI

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
    var isSensitive: Bool // Detected as password, token, or API key
    var thumbnailData: Data? // Thumbnail for image files

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
        isSensitive: Bool = false,
        thumbnailData: Data? = nil
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
        self.isSensitive = isSensitive
        self.thumbnailData = thumbnailData
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

    /// Returns the thumbnail image if available (for image files)
    var thumbnailImage: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }

    /// Returns the first file path (for file type items)
    var firstFilePath: String? {
        guard contentTypeEnum == .file else { return nil }
        return String(data: content, encoding: .utf8)?.components(separatedBy: "\n").first
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

// MARK: - Drag and Drop Support

extension ClipboardItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { item in
            item.content
        }
    }
}

/// Provides drag data for ClipboardItem
struct ClipboardItemDragData: Transferable {
    let item: ClipboardItem

    static var transferRepresentation: some TransferRepresentation {
        // Text content
        DataRepresentation(exportedContentType: .utf8PlainText) { dragData in
            if let text = dragData.item.textContent {
                return text.data(using: .utf8) ?? Data()
            }
            return Data()
        }
        .exportingCondition { dragData in
            dragData.item.contentTypeEnum == .text || dragData.item.contentTypeEnum == .url
        }

        // Image content
        DataRepresentation(exportedContentType: .png) { dragData in
            dragData.item.content
        }
        .exportingCondition { dragData in
            dragData.item.contentTypeEnum == .image
        }

        // File URL content
        DataRepresentation(exportedContentType: .fileURL) { dragData in
            if let path = dragData.item.firstFilePath,
               let url = URL(string: "file://\(path)") {
                return url.absoluteString.data(using: .utf8) ?? Data()
            }
            return Data()
        }
        .exportingCondition { dragData in
            dragData.item.contentTypeEnum == .file
        }
    }
}

/// NSItemProvider support for AppKit drag and drop
extension ClipboardItem {
    func makeItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        switch contentTypeEnum {
        case .text, .url:
            if let text = textContent {
                provider.registerObject(text as NSString, visibility: .all)
            }

        case .image:
            if let nsImage = NSImage(data: content) {
                provider.registerObject(nsImage, visibility: .all)
            }

        case .file:
            if let pathsString = String(data: content, encoding: .utf8) {
                let paths = pathsString.components(separatedBy: "\n")
                for path in paths {
                    let url = URL(fileURLWithPath: path)
                    provider.registerObject(url as NSURL, visibility: .all)
                }
            }
        }

        return provider
    }
}
