import SwiftUI
import SwiftData

/// Drag preview that captures data upfront to avoid SwiftData threading issues
struct ClipboardItemDragPreview: View {
    // Captured values from ClipboardItem (thread-safe)
    let contentType: ContentType
    let displayText: String
    let textContent: String?
    let content: Data
    let thumbnailImage: NSImage?

    private var previewSize: CGFloat { 80 }

    /// Initialize by capturing all necessary data from the ClipboardItem
    /// MUST be called on the main thread
    @MainActor
    init(item: ClipboardItem) {
        self.contentType = item.contentTypeEnum
        self.displayText = item.displayText
        self.textContent = item.textContent
        self.content = item.content
        self.thumbnailImage = item.thumbnailImage
    }

    var body: some View {
        VStack(spacing: 4) {
            previewContent
                .frame(width: previewSize, height: previewSize)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            Text(contentType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
        }
        .padding(8)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch contentType {
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayText.prefix(50))
                        .font(.system(size: 9))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(6)
            }

        case .image:
            if let nsImage = NSImage(data: content) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: previewSize, height: previewSize)
                    .clipped()
            } else {
                imagePlaceholder
            }

        case .url:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))

                VStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)

                    if let text = textContent {
                        Text(text.prefix(30))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(4)
            }

        case .file:
            ZStack {
                if let thumbnail = thumbnailImage {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: previewSize, height: previewSize)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.orange)
                                .cornerRadius(4)
                                .padding(4)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))

                    VStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)

                        if let text = textContent {
                            Text(text.prefix(20))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))

            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        // Text preview
        ClipboardItemDragPreview(
            contentType: .text,
            displayText: "Hello, World! This is some sample text.",
            textContent: "Hello, World! This is some sample text.",
            content: "Hello, World! This is some sample text.".data(using: .utf8)!,
            thumbnailImage: nil
        )

        // URL preview
        ClipboardItemDragPreview(
            contentType: .url,
            displayText: "https://apple.com",
            textContent: "https://apple.com",
            content: "https://apple.com".data(using: .utf8)!,
            thumbnailImage: nil
        )
    }
    .padding()
}

// Internal initializer for previews only
extension ClipboardItemDragPreview {
    init(contentType: ContentType, displayText: String, textContent: String?, content: Data, thumbnailImage: NSImage?) {
        self.contentType = contentType
        self.displayText = displayText
        self.textContent = textContent
        self.content = content
        self.thumbnailImage = thumbnailImage
    }
}
