import SwiftUI
import SwiftData

struct PopoutBoardView: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""
    @State private var selectedType: ContentType?
    @State private var previewingImage: ClipboardItem?
    @State private var isFloating = AppSettings.shared.popoutWindowFloating

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
        .frame(minWidth: 300, minHeight: 400)
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

            // Float toggle button
            Button(action: {
                isFloating.toggle()
                if let controller = PopoutBoardWindowController.shared {
                    controller.setFloating(isFloating)
                }
            }) {
                Image(systemName: isFloating ? "pin.fill" : "pin")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFloating ? (settings.accentColor ?? .accentColor) : .secondary)
            .help(isFloating ? "Unpin from top (always on top)" : "Pin to top (always on top)")
            .accessibilityLabel(isFloating ? "Window pinned" : "Pin window")
            .accessibilityAddTraits(isFloating ? .isSelected : [])

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

// MARK: - Preview

#Preview {
    PopoutBoardView()
        .environmentObject(ClipboardService())
        .frame(width: 340, height: 500)
}
