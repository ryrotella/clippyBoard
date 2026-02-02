import SwiftUI
import SwiftData

struct ClipboardItemRow: View {
    let item: ClipboardItem
    var isRevealed: Bool = true // For sensitive items: whether content is revealed
    var onCopyTapped: (() -> Void)? = nil // Callback for copy button tap

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var authService = AuthenticationService.shared

    // Dynamic Type scaled sizes (combined with user's text size preference)
    @ScaledMetric(relativeTo: .caption2) private var baseBadgeFont: CGFloat = DesignTokens.badgeFont
    @ScaledMetric(relativeTo: .body) private var baseBodyFont: CGFloat = DesignTokens.bodyFont
    @ScaledMetric(relativeTo: .body) private var baseIconSize: CGFloat = DesignTokens.iconSize
    @ScaledMetric(relativeTo: .body) private var baseLargeIconSize: CGFloat = DesignTokens.largeIconSize

    private var badgeFont: CGFloat { baseBadgeFont * settings.textSizeScale }
    private var bodyFont: CGFloat { baseBodyFont * settings.textSizeScale }
    private var iconSize: CGFloat { baseIconSize * settings.textSizeScale }
    private var largeIconSize: CGFloat { baseLargeIconSize * settings.textSizeScale }

    private var isImage: Bool {
        item.contentTypeEnum == .image
    }

    private var isImageFile: Bool {
        item.contentTypeEnum == .file && item.thumbnailData != nil
    }

    /// Cached image for this item (decoded once, used multiple times)
    private var cachedImage: NSImage? {
        guard isImage else { return nil }
        return ImageCache.shared.image(for: item.content, key: item.id.uuidString)
    }

    /// Whether this item has visual content (image or image file)
    private var hasVisualContent: Bool {
        isImage || isImageFile
    }

    /// Image height for visual content - adapts to actual image aspect ratio
    private var imageDisplayHeight: CGFloat {
        if let nsImage = cachedImage {
            let aspectRatio = nsImage.size.width / nsImage.size.height
            // Constrain height based on aspect ratio, min 80, max 200
            let calculatedHeight = 320 / aspectRatio
            return min(max(calculatedHeight, 80), 200)
        }
        if let thumbnail = item.thumbnailImage {
            let aspectRatio = thumbnail.size.width / thumbnail.size.height
            let calculatedHeight = 320 / aspectRatio
            return min(max(calculatedHeight, 80), 200)
        }
        return 120
    }

    private var rowPadding: CGFloat {
        settings.rowDensity.verticalPadding
    }

    private var contentSpacing: CGFloat {
        settings.rowDensity.spacing
    }

    /// Whether the content should be hidden (sensitive and not authenticated)
    private var shouldHideContent: Bool {
        item.isSensitive && !isRevealed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main content area - the hero
            mainContentView

            // Metadata row: source, time, indicators, copy button
            metadataRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, rowPadding + 2)
        .background(rowBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: settings.isHighContrast ? 1 : 0)
        )
        .contentShape(Rectangle())
        .draggable(ClipboardItemDragData(item: item)) {
            ClipboardItemDragPreview(item: item)
        }
    }

    // MARK: - Main Content View (Hero)

    @ViewBuilder
    private var mainContentView: some View {
        if shouldHideContent {
            // Sensitive content placeholder
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                Text("Sensitive content - tap to reveal")
                    .font(.system(size: bodyFont))
                    .italic()
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        } else if isImage {
            // Image content - full width, prominent
            imageContentView
        } else if isImageFile {
            // Image file - full width thumbnail
            imageFileContentView
        } else {
            // Text/URL/File content - text is the hero
            textContentView
        }
    }

    @ViewBuilder
    private var imageContentView: some View {
        if let nsImage = cachedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: imageDisplayHeight)
                .cornerRadius(8)
                .clipped()
                .accessibilityHidden(true)
        } else {
            // Placeholder for loading image
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var imageFileContentView: some View {
        if let thumbnail = item.thumbnailImage {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageDisplayHeight)
                    .cornerRadius(8)
                    .clipped()

                // File badge
                Image(systemName: "doc.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.orange)
                    .cornerRadius(6)
                    .padding(6)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var textContentView: some View {
        HStack(alignment: .top, spacing: 10) {
            // Small type indicator icon
            typeIcon
                .frame(width: 28, height: 28)

            // Text content - the main focus
            Text(item.displayText.isEmpty ? "(No text)" : item.displayText)
                .font(.system(size: bodyFont * 1.1))
                .foregroundStyle(.primary)
                .lineLimit(settings.maxPreviewLines + 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.contentTypeEnum {
        case .text:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                )
        case .url:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.15))
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                )
        case .file:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    Image(systemName: "doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                )
        case .image:
            EmptyView()
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 8) {
            // Source app
            if settings.showSourceAppIcon, let appName = item.sourceAppName {
                HStack(spacing: 4) {
                    if let icon = item.sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    if !settings.simplifiedDisplay {
                        Text(appName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Separator dot if we have both source and timestamp
            if settings.showSourceAppIcon && item.sourceAppName != nil && settings.showTimestamps {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }

            // Timestamp
            if settings.showTimestamps {
                Text(item.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Status indicators
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(settings.accentColor ?? .orange)
            }

            if item.isSensitive {
                Image(systemName: shouldHideContent ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(shouldHideContent ? .red : .green)
            }

            Spacer()

            // Copy button
            if settings.showCopyButton {
                Button(action: {
                    onCopyTapped?()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .accessibilityLabel("Copy")
            }
        }
    }

    private var rowBackground: Color {
        if settings.isHighContrast {
            return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    private var borderColor: Color {
        if settings.isHighContrast {
            return settings.effectiveSeparatorColor
        }
        return .clear
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
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
    .frame(width: 380)
}
