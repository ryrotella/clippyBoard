import SwiftUI
import SwiftData

struct ClipboardItemRow: View {
    let item: ClipboardItem
    var isRevealed: Bool = true // For sensitive items: whether content is revealed

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

    private var thumbnailSize: CGFloat {
        // Show larger thumbnail for images and image files
        (isImage || isImageFile) ? settings.thumbnailSizeSetting.largeSize : settings.thumbnailSizeSetting.smallSize
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
        HStack(spacing: contentSpacing) {
            // Content type icon or thumbnail
            contentPreview
                .frame(width: thumbnailSize, height: thumbnailSize)

            // Main content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Content type badge
                    if settings.showTypeBadges {
                        Text(item.contentTypeEnum.displayName)
                            .font(.system(size: badgeFont, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.15))
                            .foregroundStyle(badgeColor)
                            .cornerRadius(4)
                    }

                    // Image dimensions
                    if isImage, let nsImage = cachedImage {
                        Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height))")
                            .font(.system(size: badgeFont))
                            .foregroundStyle(.secondary)
                    }

                    // Pin indicator
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(settings.accentColor ?? .orange)
                    }

                    // Sensitive indicator
                    if item.isSensitive {
                        Image(systemName: shouldHideContent ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(shouldHideContent ? .red : .green)
                    }

                    Spacer()

                    // Timestamp
                    if settings.showTimestamps {
                        Text(item.relativeTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Content preview (hide for images)
                if !isImage {
                    if shouldHideContent {
                        // Show placeholder for sensitive hidden content
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: bodyFont * 0.9))
                            Text("Sensitive content - tap to reveal")
                                .font(.system(size: bodyFont * 0.9))
                                .italic()
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                        Text(item.displayText.isEmpty ? "(No text)" : item.displayText)
                            .font(.system(size: bodyFont))
                            .foregroundStyle(.primary)
                            .lineLimit(settings.maxPreviewLines)
                            .truncationMode(.tail)
                    }
                }

                // Source app
                if settings.showSourceAppIcon, let appName = item.sourceAppName {
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
        .padding(.vertical, rowPadding)
        .background(rowBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: settings.isHighContrast ? 1 : 0)
        )
        .contentShape(Rectangle())
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

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.contentTypeEnum {
        case .text:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.secondary)
                )
                .accessibilityHidden(true)

        case .image:
            if let nsImage = cachedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .cornerRadius(6)
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: largeIconSize))
                            .foregroundStyle(.secondary)
                    )
                    .accessibilityHidden(true)
            }

        case .url:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.blue)
                )
                .accessibilityHidden(true)

        case .file:
            // Show thumbnail for image files, otherwise show file icon
            if let thumbnail = item.thumbnailImage {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .cornerRadius(6)
                    .clipped()
                    .overlay(
                        // Small file badge in corner to indicate it's a file
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.orange)
                            .cornerRadius(4)
                            .padding(4),
                        alignment: .bottomTrailing
                    )
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: iconSize))
                            .foregroundStyle(.orange)
                    )
                    .accessibilityHidden(true)
            }
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
