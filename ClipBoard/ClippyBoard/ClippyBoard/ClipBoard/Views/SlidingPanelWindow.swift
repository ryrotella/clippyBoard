import SwiftUI
import AppKit
import SwiftData

// MARK: - Sliding Panel Window Controller

@MainActor
class SlidingPanelWindowController: NSObject, ObservableObject {
    static var shared: SlidingPanelWindowController?

    private var panel: NSPanel?
    private var clipboardService: ClipboardService
    private var modelContainer: ModelContainer
    private var isDetached = false
    private var dragStartLocation: NSPoint?

    @Published var isVisible = false

    private init(clipboardService: ClipboardService, modelContainer: ModelContainer) {
        self.clipboardService = clipboardService
        self.modelContainer = modelContainer
        super.init()
        setupPanel()
        setupNotifications()
    }

    static func createShared(clipboardService: ClipboardService, modelContainer: ModelContainer) -> SlidingPanelWindowController {
        if shared == nil {
            shared = SlidingPanelWindowController(clipboardService: clipboardService, modelContainer: modelContainer)
        }
        return shared!
    }

    private func setupPanel() {
        let settings = AppSettings.shared
        let screen = screenWithMouse() ?? NSScreen.main ?? NSScreen.screens.first!
        let panelSize = calculatePanelSize(for: screen)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel?.isFloatingPanel = true
        // Use normal level if user wants windows to overlap the panel
        panel?.level = settings.panelAlwaysOnTop ? .floating : .normal
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        panel?.hasShadow = true
        panel?.isMovableByWindowBackground = false
        panel?.animationBehavior = .utilityWindow

        let contentView = SlidingPanelContentView(
            onDragStart: { [weak self] location in
                self?.dragStartLocation = location
            },
            onDragChanged: { [weak self] location in
                self?.handleDrag(to: location)
            },
            onDragEnded: { [weak self] location in
                self?.handleDragEnd(at: location)
            },
            onClose: { [weak self] in
                self?.hidePanel()
            }
        )
        .environmentObject(clipboardService)
        .modelContainer(modelContainer)

        panel?.contentView = NSHostingView(rootView: contentView)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissNotification),
            name: .dismissClipboardUI,
            object: nil
        )

        // Observe settings changes to update panel level
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleDismissNotification() {
        hidePanel()
    }

    @objc private func handleSettingsChange() {
        // Update panel level when settings change
        let settings = AppSettings.shared
        panel?.level = settings.panelAlwaysOnTop ? .floating : .normal
    }

    /// Returns the screen containing the mouse cursor
    private func screenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }

    private func calculatePanelSize(for screen: NSScreen) -> NSSize {
        let settings = AppSettings.shared
        let edge = settings.panelEdgeSetting

        switch edge {
        case .left, .right:
            return NSSize(width: settings.slidingPanelWidth, height: screen.frame.height)
        case .top, .bottom:
            return NSSize(width: screen.frame.width, height: settings.slidingPanelHeight)
        }
    }

    private func calculateOffscreenFrame(for screen: NSScreen) -> NSRect {
        let settings = AppSettings.shared
        let panelSize = calculatePanelSize(for: screen)
        let screenFrame = screen.frame

        switch settings.panelEdgeSetting {
        case .left:
            return NSRect(x: screenFrame.minX - panelSize.width, y: screenFrame.minY, width: panelSize.width, height: screenFrame.height)
        case .right:
            return NSRect(x: screenFrame.maxX, y: screenFrame.minY, width: panelSize.width, height: screenFrame.height)
        case .top:
            return NSRect(x: screenFrame.minX, y: screenFrame.maxY, width: screenFrame.width, height: panelSize.height)
        case .bottom:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY - panelSize.height, width: screenFrame.width, height: panelSize.height)
        }
    }

    private func calculateOnscreenFrame(for screen: NSScreen) -> NSRect {
        let settings = AppSettings.shared
        let panelSize = calculatePanelSize(for: screen)
        let screenFrame = screen.frame

        switch settings.panelEdgeSetting {
        case .left:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY, width: panelSize.width, height: screenFrame.height)
        case .right:
            return NSRect(x: screenFrame.maxX - panelSize.width, y: screenFrame.minY, width: panelSize.width, height: screenFrame.height)
        case .top:
            return NSRect(x: screenFrame.minX, y: screenFrame.maxY - panelSize.height, width: screenFrame.width, height: panelSize.height)
        case .bottom:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: panelSize.height)
        }
    }

    // MARK: - Show/Hide

    func showPanel() {
        guard !isVisible else { return }
        clipboardService.refreshItems()

        if isDetached {
            // Show as floating window
            panel?.orderFrontRegardless()
            isVisible = true
            return
        }

        // Get the screen where the mouse is located
        guard let screen = screenWithMouse() else { return }

        // Slide in from edge on the correct screen
        let startFrame = calculateOffscreenFrame(for: screen)
        let endFrame = calculateOnscreenFrame(for: screen)

        panel?.setFrame(startFrame, display: false)
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().setFrame(endFrame, display: true)
        }

        isVisible = true
    }

    func hidePanel() {
        guard isVisible else { return }

        if isDetached {
            panel?.orderOut(nil)
            isVisible = false
            return
        }

        // Get the screen where the panel currently is
        let screen = panel?.screen ?? screenWithMouse() ?? NSScreen.main
        guard let screen = screen else {
            panel?.orderOut(nil)
            isVisible = false
            return
        }

        // Slide out to edge
        let endFrame = calculateOffscreenFrame(for: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.isVisible = false
        }
    }

    /// Close and clean up the panel (call on app termination)
    func closePanel() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        isVisible = false
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Drag to Detach

    private func handleDrag(to location: NSPoint) {
        guard panel != nil, !isDetached else { return }

        let settings = AppSettings.shared
        let threshold: CGFloat = 100
        let screen = panel?.screen ?? screenWithMouse() ?? NSScreen.main

        // Check if dragged far enough from edge to detach
        switch settings.panelEdgeSetting {
        case .left:
            if let screen = screen, location.x > screen.frame.minX + threshold {
                detachPanel(at: location)
            }
        case .right:
            if let screen = screen, location.x < screen.frame.maxX - threshold {
                detachPanel(at: location)
            }
        case .top:
            if let screen = screen, location.y < screen.frame.maxY - threshold {
                detachPanel(at: location)
            }
        case .bottom:
            if let screen = screen, location.y > screen.frame.minY + threshold {
                detachPanel(at: location)
            }
        }
    }

    private func handleDragEnd(at location: NSPoint) {
        if isDetached {
            // Save floating window position
            if let frame = panel?.frame {
                AppSettings.shared.popoutWindowX = Double(frame.origin.x)
                AppSettings.shared.popoutWindowY = Double(frame.origin.y)
            }
        }
        dragStartLocation = nil
    }

    private func detachPanel(at location: NSPoint) {
        guard !isDetached else { return }
        isDetached = true

        // Convert to floating window style
        panel?.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        panel?.isMovableByWindowBackground = true
        panel?.level = .floating

        // Set new frame centered on drag location
        let settings = AppSettings.shared
        let width = settings.slidingPanelWidth
        let height = min(settings.slidingPanelHeight, 600)

        let newFrame = NSRect(
            x: location.x - width / 2,
            y: location.y - height / 2,
            width: width,
            height: height
        )

        panel?.setFrame(newFrame, display: true)
    }

    func reattachPanel() {
        isDetached = false
        setupPanel()
    }
}

// MARK: - Sliding Panel Content View

struct SlidingPanelContentView: View {
    @EnvironmentObject private var clipboardService: ClipboardService
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var toastManager = ToastManager.shared
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""
    @State private var selectedType: ContentType?
    @State private var previewingImage: ClipboardItem?
    @State private var showShortcutHint = false

    var onDragStart: ((NSPoint) -> Void)?
    var onDragChanged: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle / header
            panelHeader

            Divider()

            // Content
            ClipboardContentView(
                searchText: $searchText,
                selectedType: $selectedType,
                previewingImage: $previewingImage,
                onSettingsTapped: { openSettings() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
        .opacity(settings.windowOpacity)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .toast(
            isShowing: $toastManager.isShowingCopyToast,
            message: "Copied!",
            icon: "checkmark.circle.fill",
            playSound: settings.copyFeedbackSound
        )
        .overlay(alignment: .center) {
            if showShortcutHint {
                shortcutHintOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showShortcutHint)) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                showShortcutHint = true
            }
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showShortcutHint = false
                }
            }
        }
    }

    private var shortcutHintOverlay: some View {
        VStack(spacing: 16) {
            // Keyboard icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Press \(settings.popoverShortcut.displayString)")
                    .font(.system(size: 18, weight: .semibold))

                Text("to show or hide ClipBoard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Got it") {
                withAnimation(.easeIn(duration: 0.2)) {
                    showShortcutHint = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .shadow(color: .blue.opacity(0.3), radius: 30, x: 0, y: 10)
    }

    private var panelCornerRadius: CGFloat {
        switch settings.panelEdgeSetting {
        case .left: return 0
        case .right: return 0
        case .top: return 0
        case .bottom: return 0
        }
    }

    private var panelBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            // Drag handle indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.vertical, 4)

            Spacer()

            Image(systemName: "clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("ClipBoard")
                .font(.headline)

            Spacer()

            // Close button
            Button(action: { onClose?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if let window = NSApp.keyWindow {
                        let screenLocation = NSPoint(
                            x: window.frame.origin.x + value.location.x,
                            y: window.frame.origin.y + value.location.y
                        )
                        onDragChanged?(screenLocation)
                    }
                }
                .onEnded { value in
                    if let window = NSApp.keyWindow {
                        let screenLocation = NSPoint(
                            x: window.frame.origin.x + value.location.x,
                            y: window.frame.origin.y + value.location.y
                        )
                        onDragEnded?(screenLocation)
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview {
    SlidingPanelContentView()
        .frame(width: 380, height: 600)
        .environmentObject(ClipboardService())
}
