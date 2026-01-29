import SwiftUI
import SwiftData

struct ClipboardItemRow: View {
    let item: ClipboardItem

    private var isImage: Bool {
        item.contentTypeEnum == .image
    }

    private var thumbnailSize: CGFloat {
        isImage ? 60 : 36
    }

    var body: some View {
        HStack(spacing: 10) {
            // Content type icon or thumbnail
            contentPreview
                .frame(width: thumbnailSize, height: thumbnailSize)

            // Main content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Content type badge
                    Text(item.contentTypeEnum.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .cornerRadius(4)

                    // Image dimensions
                    if isImage, let nsImage = NSImage(data: item.content) {
                        Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    // Pin indicator
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    // Timestamp
                    Text(item.relativeTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Content preview (hide for images)
                if !isImage {
                    Text(item.displayText.isEmpty ? "(No text)" : item.displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                // Source app
                if let appName = item.sourceAppName {
                    HStack(spacing: 4) {
                        if let icon = item.sourceAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                        Text(appName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.contentTypeEnum {
        case .text:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                )

        case .image:
            if let nsImage = NSImage(data: item.content) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    )
            }

        case .url:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                )

        case .file:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    Image(systemName: "doc")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                )
        }
    }

    private var badgeColor: Color {
        switch item.contentTypeEnum {
        case .text: return .gray
        case .image: return .purple
        case .file: return .orange
        case .url: return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ClipboardItemRow(item: ClipboardItem(
            content: "Hello, World!".data(using: .utf8)!,
            textContent: "Hello, World! This is a sample clipboard item that might be a bit longer.",
            contentType: "text",
            sourceApp: "com.apple.Safari",
            sourceAppName: "Safari",
            characterCount: 50,
            searchableText: "hello world"
        ))

        ClipboardItemRow(item: ClipboardItem(
            content: "https://apple.com".data(using: .utf8)!,
            textContent: "https://apple.com",
            contentType: "url",
            sourceApp: "com.apple.Safari",
            sourceAppName: "Safari",
            isPinned: true,
            characterCount: 17,
            searchableText: "https://apple.com"
        ))
    }
    .padding()
    .frame(width: 340)
}
