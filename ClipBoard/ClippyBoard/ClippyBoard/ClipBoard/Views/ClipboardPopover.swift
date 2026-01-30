import SwiftUI
import SwiftData

// MARK: - Reusable Clipboard Content View

struct ClipboardContentView: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    @ObservedObject private var settings = AppSettings.shared

    @Binding var searchText: String
    @Binding var selectedType: ContentType?
    @Binding var previewingImage: ClipboardItem?

    private var items: [ClipboardItem] {
        clipboardService.items
    }

    private var filteredItems: [ClipboardItem] {
        var result = items

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { item in
                item.searchableText.contains(searchText.lowercased())
            }
        }

        // Filter by content type
        if let type = selectedType {
            result = result.filter { $0.contentType == type.rawValue }
        }

        return result
    }

    private var pinnedItems: [ClipboardItem] {
        filteredItems.filter { $0.isPinned }
    }

    private var unpinnedItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Filter chips
            filterChips
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // Content
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsList
            }

            Divider()

            // Footer
            footerView
        }
        .sheet(item: $previewingImage) { item in
            ImagePreviewView(
                imageData: item.content,
                onClose: { previewingImage = nil },
                onCopy: {
                    clipboardService.copyToClipboard(item)
                    previewingImage = nil
                }
            )
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityHint("Type to filter clipboard items")

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Filters

    private var filterChips: some View {
        HStack(spacing: 6) {
            FilterChip(
                title: "All",
                isSelected: selectedType == nil,
                action: { selectedType = nil }
            )

            ForEach(ContentType.allCases, id: \.self) { type in
                FilterChip(
                    title: type.displayName,
                    isSelected: selectedType == type,
                    action: { selectedType = type }
                )
            }

            Spacer()
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: settings.showRowSeparators ? 0 : 4) {
                // Pinned section
                if !pinnedItems.isEmpty {
                    Section {
                        ForEach(Array(pinnedItems.enumerated()), id: \.element.id) { index, item in
                            itemRow(for: item, isLast: index == pinnedItems.count - 1 && unpinnedItems.isEmpty)
                        }
                    } header: {
                        sectionHeader("Pinned")
                    }
                }

                // Recent section
                if !unpinnedItems.isEmpty {
                    Section {
                        ForEach(Array(unpinnedItems.enumerated()), id: \.element.id) { index, item in
                            itemRow(for: item, isLast: index == unpinnedItems.count - 1)
                        }
                    } header: {
                        if !pinnedItems.isEmpty {
                            sectionHeader("Recent")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func itemRow(for item: ClipboardItem, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            ClipboardItemRow(item: item)
                .onTapGesture(count: 2) {
                    // Double-tap: preview for images, copy for others
                    if item.contentTypeEnum == .image {
                        previewingImage = item
                    } else {
                        clipboardService.copyToClipboard(item)
                    }
                }
                .onTapGesture(count: 1) {
                    // Single tap: always copy
                    clipboardService.copyToClipboard(item)
                }
                .contextMenu {
                    itemContextMenu(for: item)
                }

            // Row separator
            if settings.showRowSeparators && !isLast {
                settings.effectiveSeparatorColor
                    .frame(height: 1)
                    .padding(.vertical, 4)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func itemContextMenu(for item: ClipboardItem) -> some View {
        Button(action: { clipboardService.copyToClipboard(item) }) {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if item.contentTypeEnum == .image {
            Button(action: { previewingImage = item }) {
                Label("Preview", systemImage: "eye")
            }
        }

        // Transform submenu for text-based content
        if item.contentTypeEnum == .text || item.contentTypeEnum == .url {
            Menu {
                ForEach(TextTransformation.allCases, id: \.self) { transform in
                    Button(action: {
                        if let text = item.textContent {
                            clipboardService.copyTransformedText(transform.apply(to: text))
                        }
                    }) {
                        Label(transform.rawValue, systemImage: transform.icon)
                    }
                }
            } label: {
                Label("Transform", systemImage: "wand.and.stars")
            }
        }

        Button(action: { clipboardService.togglePin(item) }) {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
        }

        Divider()

        Button(role: .destructive, action: { clipboardService.deleteItem(item) }) {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(searchText.isEmpty ? "No clipboard history" : "No results found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(searchText.isEmpty ? "Copy something to get started" : "Try a different search term")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

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
            .accessibilityLabel("Clear history")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Clipboard Popover

struct ClipboardPopover: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""
    @State private var selectedType: ContentType?
    @State private var previewingImage: ClipboardItem?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Shared content
            ClipboardContentView(
                searchText: $searchText,
                selectedType: $selectedType,
                previewingImage: $previewingImage
            )
        }
        .frame(width: 340, height: 480)
        .opacity(settings.windowOpacity)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "clipboard")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("ClipBoard")
                .font(.headline)

            Spacer()

            Button(action: {
                NotificationCenter.default.post(name: .openPopoutBoard, object: nil)
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in popout window (⌘⇧B)")
            .accessibilityLabel("Open popout window")

            Button(action: {
                openSettings()
            }) {
                Image(systemName: "gear")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Filter Chip

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
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    ClipboardPopover()
        .environmentObject(ClipboardService())
}
