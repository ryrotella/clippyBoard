import SwiftUI
import SwiftData

// MARK: - Reusable Clipboard Content View

struct ClipboardContentView: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var authService = AuthenticationService.shared
    @ObservedObject private var toastManager = ToastManager.shared

    @Binding var searchText: String
    @Binding var selectedType: ContentType?
    @Binding var previewingImage: ClipboardItem?
    var onSettingsTapped: (() -> Void)? = nil

    /// Debounced search text that updates after a delay
    @State private var debouncedSearchText = ""

    /// Set of item IDs that have been revealed (authenticated) this session
    @State private var revealedItems: Set<UUID> = []

    private var items: [ClipboardItem] {
        clipboardService.items
    }

    private var filteredItems: [ClipboardItem] {
        var result = items

        // Filter by debounced search text
        if !debouncedSearchText.isEmpty {
            result = result.filter { item in
                item.searchableText.contains(debouncedSearchText.lowercased())
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
        .task(id: searchText) {
            // Debounce search by waiting 300ms before applying
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                debouncedSearchText = searchText
            } catch {
                // Task was cancelled (new search text entered), which is expected
            }
        }
        .toast(
            isShowing: $toastManager.isShowingCopyToast,
            message: "Copied!",
            icon: "checkmark.circle.fill",
            playSound: settings.copyFeedbackSound
        )
        .onChange(of: searchText) { _, newValue in
            // If search is cleared, update immediately without debounce
            if newValue.isEmpty {
                debouncedSearchText = ""
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityLabel("Search")
                .accessibilityHint("Type to filter clipboard items")

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
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

            // Settings button (shown when callback provided, e.g., in sliding panel)
            if let onSettings = onSettingsTapped {
                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
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
        let isRevealed = !item.isSensitive || revealedItems.contains(item.id)

        VStack(spacing: 0) {
            ClipboardItemRow(
                item: item,
                isRevealed: isRevealed,
                onCopyTapped: {
                    // Copy button: copy to clipboard only (no paste)
                    handleCopyOnly(item)
                }
            )
                .onTapGesture(count: 2) {
                    // Double-tap: preview for images, copy for others
                    if item.contentTypeEnum == .image {
                        previewingImage = item
                    } else {
                        handlePaste(item)
                    }
                }
                .onTapGesture(count: 1) {
                    // Single tap: reveal if sensitive, otherwise paste
                    if item.isSensitive && !isRevealed {
                        handleReveal(item)
                    } else {
                        handlePaste(item)
                    }
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

    /// Handle revealing sensitive content with authentication
    private func handleReveal(_ item: ClipboardItem) {
        Task {
            let authenticated = await authService.authenticate(
                for: item.id,
                reason: "Authenticate to reveal sensitive content"
            )
            if authenticated {
                revealedItems.insert(item.id)
            }
        }
    }

    /// Handle copying with authentication for sensitive items (copy only, no paste)
    private func handleCopyOnly(_ item: ClipboardItem) {
        Task {
            let success = await clipboardService.copyToClipboardWithAuth(item)
            if success {
                if item.isSensitive {
                    revealedItems.insert(item.id)
                }
                // Show copy feedback
                NotificationCenter.default.post(name: .didCopyItem, object: nil)
            }
        }
    }

    /// Handle paste action (copy to clipboard and paste to active app if enabled)
    private func handlePaste(_ item: ClipboardItem) {
        Task {
            let success = await clipboardService.copyToClipboardWithAuth(item)
            if success {
                if item.isSensitive {
                    revealedItems.insert(item.id)
                }
                // Show copy feedback
                NotificationCenter.default.post(name: .didCopyItem, object: nil)

                // If click-to-paste is enabled, paste to active app
                if AppSettings.shared.clickToPaste {
                    // Close popover/panel first to return focus
                    NotificationCenter.default.post(name: .dismissClipboardUI, object: nil)
                    // Small delay to allow window to close
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    _ = await AccessibilityService.shared.simulatePaste()
                }
            }
        }
    }

    /// Legacy copy handler for context menu
    private func handleCopy(_ item: ClipboardItem) {
        handleCopyOnly(item)
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
        // Copy action (with auth for sensitive items)
        Button(action: { handleCopy(item) }) {
            Label(item.isSensitive ? "Copy (Requires Auth)" : "Copy", systemImage: "doc.on.doc")
        }

        // Reveal action for sensitive items
        if item.isSensitive && !revealedItems.contains(item.id) {
            Button(action: { handleReveal(item) }) {
                Label("Reveal Content", systemImage: "lock.open")
            }
        }

        if item.contentTypeEnum == .image {
            Button(action: { previewingImage = item }) {
                Label("Preview", systemImage: "eye")
            }
        }

        // Transform submenu for text-based content (only if revealed or not sensitive)
        if (item.contentTypeEnum == .text || item.contentTypeEnum == .url) &&
           (!item.isSensitive || revealedItems.contains(item.id)) {
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
        .frame(width: 380, height: 520)
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
                .font(.subheadline)
                .fontWeight(isSelected ? .medium : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? accentColor : .secondary)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
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
