import SwiftUI
import SwiftData

struct ClipboardPopover: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    @State private var searchText = ""
    @State private var selectedType: ContentType?
    @State private var previewingImage: ClipboardItem?

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
            // Header
            headerView

            Divider()

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
        .frame(width: 340, height: 480)
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "clipboard")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("ClipBoard")
                .font(.headline)

            Spacer()

            Button(action: {}) {
                Image(systemName: "gear")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
            LazyVStack(spacing: 0) {
                // Pinned section
                if !pinnedItems.isEmpty {
                    Section {
                        ForEach(pinnedItems) { item in
                            itemRow(for: item)
                        }
                    } header: {
                        sectionHeader("Pinned")
                    }
                }

                // Recent section
                if !unpinnedItems.isEmpty {
                    Section {
                        ForEach(unpinnedItems) { item in
                            itemRow(for: item)
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
    private func itemRow(for item: ClipboardItem) -> some View {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ClipboardPopover()
        .environmentObject(ClipboardService())
}
