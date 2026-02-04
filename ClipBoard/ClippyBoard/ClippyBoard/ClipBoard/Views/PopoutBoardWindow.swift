import AppKit
import SwiftUI
import SwiftData

@MainActor
class PopoutBoardWindowController: NSWindowController, NSWindowDelegate {
    static var shared: PopoutBoardWindowController?

    private var clipboardService: ClipboardService?
    private var modelContainer: ModelContainer?

    static func createShared(clipboardService: ClipboardService, modelContainer: ModelContainer) -> PopoutBoardWindowController {
        if let existing = shared {
            existing.clipboardService = clipboardService
            existing.modelContainer = modelContainer
            return existing
        }

        let controller = PopoutBoardWindowController(clipboardService: clipboardService, modelContainer: modelContainer)
        shared = controller
        return controller
    }

    private init(clipboardService: ClipboardService, modelContainer: ModelContainer) {
        self.clipboardService = clipboardService
        self.modelContainer = modelContainer

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "ClipBoard"
        window.minSize = NSSize(width: 300, height: 400)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false

        super.init(window: window)

        window.delegate = self

        setupContent()
        loadFrame()
        applyFloatingState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let clipboardService = clipboardService, let modelContainer = modelContainer else { return }

        let contentView = PopoutBoardView()
            .environmentObject(clipboardService)
            .modelContainer(modelContainer)

        window?.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Frame Persistence

    private func loadFrame() {
        let settings = AppSettings.shared
        let frame = NSRect(
            x: settings.popoutWindowX,
            y: settings.popoutWindowY,
            width: settings.popoutWindowWidth,
            height: settings.popoutWindowHeight
        )

        // Ensure the window is at least partially visible on screen
        if let screen = NSScreen.main, screen.visibleFrame.intersects(frame) {
            window?.setFrame(frame, display: true)
        } else {
            // Reset to default position if off-screen
            window?.center()
        }
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let settings = AppSettings.shared
        settings.popoutWindowX = frame.origin.x
        settings.popoutWindowY = frame.origin.y
        settings.popoutWindowWidth = frame.width
        settings.popoutWindowHeight = frame.height
    }

    // MARK: - Floating State

    func setFloating(_ floating: Bool) {
        window?.level = floating ? .floating : .normal
        AppSettings.shared.popoutWindowFloating = floating
    }

    private func applyFloatingState() {
        let floating = AppSettings.shared.popoutWindowFloating
        window?.level = floating ? .floating : .normal
    }

    // MARK: - Window Management

    func showWindow() {
        guard let window = window else { return }

        if !window.isVisible {
            loadFrame()
            applyFloatingState()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    /// Close and clean up the window (call on app termination)
    func closeWindow() {
        saveFrame()
        window?.orderOut(nil)
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowWillClose(_ notification: Notification) {
        // Just hide, don't actually close
        window?.orderOut(nil)
    }
}
