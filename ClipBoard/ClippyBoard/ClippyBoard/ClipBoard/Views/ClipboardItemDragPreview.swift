import SwiftUI

struct ClipboardItemDragPreview: View {
    let item: ClipboardItem

    private var previewSize: CGFloat { 80 }

    var body: some View {
        VStack(spacing: 4) {
            previewContent
                .frame(width: previewSize, height: previewSize)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            Text(item.contentTypeEnum.displayName)
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
        switch item.contentTypeEnum {
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText.prefix(50))
                        .font(.system(size: 9))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(6)
            }

        case .image:
            if let nsImage = NSImage(data: item.content) {
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

                    if let text = item.textContent {
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
                if let thumbnail = item.thumbnailImage {
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

                        if let text = item.textContent {
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
        ClipboardItemDragPreview(item: ClipboardItem(
            content: "Hello, World! This is some sample text.".data(using: .utf8)!,
            textContent: "Hello, World! This is some sample text.",
            contentType: "text",
            sourceApp: nil,
            sourceAppName: nil,
            characterCount: 40,
            searchableText: "hello"
        ))

        ClipboardItemDragPreview(item: ClipboardItem(
            content: "https://apple.com".data(using: .utf8)!,
            textContent: "https://apple.com",
            contentType: "url",
            sourceApp: nil,
            sourceAppName: nil,
            characterCount: 17,
            searchableText: "apple"
        ))
    }
    .padding()
}
