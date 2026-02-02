import AppKit
import SwiftUI
import SwiftData
import Carbon
import os

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusMenu: NSMenu!
    private var clipboardService: ClipboardService!
    private var screenshotService: ScreenshotService!
    private var modelContainer: ModelContainer!
    private var popoutWindowController: PopoutBoardWindowController?
    private var slidingPanelController: SlidingPanelWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var popoutHotKeyRef: EventHotKeyRef?
    private var quickAccessHotKeyRefs: [EventHotKeyRef?] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon but allow app to appear in Force Quit menu
        // This replaces LSUIElement which prevents Force Quit visibility
        NSApp.setActivationPolicy(.accessory)

        // Initialize model container
        setupModelContainer()

        // Initialize clipboard service
        clipboardService = ClipboardService()
        clipboardService.setModelContainer(modelContainer)
        clipboardService.startMonitoring()

        // Initialize screenshot service
        screenshotService = ScreenshotService()
        screenshotService.setModelContainer(modelContainer)
        screenshotService.onScreenshotCaptured = { [weak self] in
            self?.clipboardService.refreshItems()
            self?.triggerCaptureAnimation()
        }
        screenshotService.startMonitoring()

        // Initialize local API server
        LocalAPIServer.shared.setModelContainer(modelContainer)
        if AppSettings.shared.apiEnabled {
            LocalAPIServer.shared.start()
        }

        // Setup status bar item
        setupStatusItem()

        // Setup popover
        setupPopover()

        // Setup global hotkeys
        setupHotkeys()

        // Observe capture events to animate icon
        setupCaptureObserver()

        // Observe hotkey notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopover),
            name: .toggleClipboardPopover,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopoutBoard),
            name: .togglePopoutBoard,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPopoutBoard),
            name: .openPopoutBoard,
            object: nil
        )

        // Show onboarding if first launch
        checkOnboarding()
    }

    private func checkOnboarding() {
        if !AppSettings.shared.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        }
    }

    private func showOnboarding() {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.title = "Welcome to ClipBoard"
        onboardingWindow.center()
        onboardingWindow.contentView = NSHostingView(rootView: OnboardingView())
        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupModelContainer() {
        let schema = Schema([
            ClipboardItem.self,
            Pinboard.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.database.error("Failed to create ModelContainer: \(error.localizedDescription, privacy: .public)")

            // Attempt recovery by deleting corrupted database
            if attemptDatabaseRecovery(schema: schema, configuration: modelConfiguration) {
                AppLogger.database.info("Database recovery successful")
            } else {
                // Show alert to user and quit
                showDatabaseErrorAlert(error: error)
                return
            }
        }

        // Ensure default pinboard exists
        guard modelContainer != nil else { return }
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Pinboard>(
            predicate: #Predicate { $0.isDefault == true }
        )

        do {
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                let defaultPinboard = Pinboard.createDefault()
                context.insert(defaultPinboard)
                try context.save()
            }
        } catch {
            AppLogger.database.error("Failed to ensure default pinboard: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func attemptDatabaseRecovery(schema: Schema, configuration: ModelConfiguration) -> Bool {
        // Get the default SwiftData store URL
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }

        let storeURL = applicationSupportURL.appendingPathComponent("default.store")

        // Delete the corrupted database files
        let fileManager = FileManager.default
        let filesToDelete = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]

        for file in filesToDelete {
            try? fileManager.removeItem(at: file)
        }

        AppLogger.database.info("Deleted corrupted database files, attempting to recreate")

        // Try to create the container again
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            return true
        } catch {
            AppLogger.database.error("Failed to recreate ModelContainer after recovery: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func showDatabaseErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Database Error"
        alert.informativeText = "ClipBoard could not initialize its database. Your clipboard history may have been corrupted.\n\nError: \(error.localizedDescription)\n\nThe app will now quit. Please try restarting the app."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
            // Use sendAction to detect both left and right clicks
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
        }

        // Setup right-click menu
        setupStatusMenu()
    }

    private func setupStatusMenu() {
        statusMenu = NSMenu()

        let openItem = NSMenuItem(title: "Open ClipBoard", action: #selector(togglePopover), keyEquivalent: "")
        openItem.target = self
        let shortcutHint = AppSettings.shared.popoverShortcut.displayString
        openItem.title = "Open ClipBoard (\(shortcutHint))"
        statusMenu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(NSMenuItem.separator())

        let incognitoItem = NSMenuItem(title: "Incognito Mode", action: #selector(toggleIncognitoMode), keyEquivalent: "")
        incognitoItem.target = self
        incognitoItem.state = AppSettings.shared.incognitoMode ? .on : .off
        statusMenu.addItem(incognitoItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClipBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // Show menu on right-click OR Option+Click (common macOS pattern)
        let showMenu = event.type == .rightMouseUp || event.modifierFlags.contains(.option)

        if showMenu {
            // Update incognito state before showing menu
            if let incognitoItem = statusMenu.item(withTitle: "Incognito Mode") {
                incognitoItem.state = AppSettings.shared.incognitoMode ? .on : .off
            }
            // Update menu item title for shortcut hint
            if let openItem = statusMenu.items.first {
                let shortcutHint = AppSettings.shared.popoverShortcut.displayString
                openItem.title = "Open ClipBoard (\(shortcutHint))"
            }
            // Show menu at the status item location
            if let button = statusItem.button {
                statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            }
        } else {
            togglePopover()
        }
    }

    @objc private func openSettings() {
        // Use the correct selector for opening Settings in SwiftUI apps
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleIncognitoMode() {
        AppSettings.shared.incognitoMode.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.animates = true

        let contentView = ClipboardPopover()
            .environmentObject(clipboardService)
            .modelContainer(modelContainer)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupHotkeys() {
        // Install single event handler for all hotkeys
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                switch hotKeyID.id {
                case 1:
                    NotificationCenter.default.post(name: .toggleClipboardPopover, object: nil)
                case 2:
                    NotificationCenter.default.post(name: .togglePopoutBoard, object: nil)
                case 3...7:
                    // Quick access shortcuts (⌥1 through ⌥5)
                    let itemIndex = Int(hotKeyID.id) - 3
                    NotificationCenter.default.post(
                        name: .quickAccessPaste,
                        object: nil,
                        userInfo: ["index": itemIndex]
                    )
                default:
                    break
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Register the hotkeys from settings
        registerHotkeys()

        // Listen for shortcut changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: .shortcutsDidChange,
            object: nil
        )

        // Listen for quick access paste notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickAccessPaste(_:)),
            name: .quickAccessPaste,
            object: nil
        )
    }

    @objc private func handleQuickAccessPaste(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let index = userInfo["index"] as? Int else { return }

        Task { @MainActor in
            // Get the item at the specified index
            let items = clipboardService.items.filter { !$0.isPinned }
            guard index < items.count else { return }

            let item = items[index]

            // Copy to clipboard
            let success = await clipboardService.copyToClipboardWithAuth(item)
            guard success else { return }

            // Simulate paste if enabled
            if AppSettings.shared.clickToPaste {
                // Small delay to ensure clipboard is ready
                try? await Task.sleep(nanoseconds: 50_000_000)
                _ = await AccessibilityService.shared.simulatePaste()
            }

            // Show feedback
            NotificationCenter.default.post(name: .didCopyItem, object: nil)
        }
    }

    @objc private func shortcutsDidChange() {
        // Unregister existing hotkeys
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = popoutHotKeyRef {
            UnregisterEventHotKey(ref)
            popoutHotKeyRef = nil
        }
        // Unregister quick access hotkeys
        for ref in quickAccessHotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        quickAccessHotKeyRefs.removeAll()

        // Register new hotkeys
        registerHotkeys()
    }

    private func registerHotkeys() {
        let settings = AppSettings.shared

        // Register popover hotkey (id: 1)
        let popoverShortcut = settings.popoverShortcut
        let popoverHotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 1)

        var popoverRef: EventHotKeyRef?
        let popoverStatus = RegisterEventHotKey(
            popoverShortcut.keyCode,
            popoverShortcut.modifiers,
            popoverHotKeyID,
            GetApplicationEventTarget(),
            0,
            &popoverRef
        )

        if popoverStatus == noErr {
            self.hotKeyRef = popoverRef
            AppLogger.hotkeys.info("Global hotkey \(popoverShortcut.displayString, privacy: .public) registered for popover")
        } else {
            AppLogger.hotkeys.error("Failed to register popover hotkey: \(popoverStatus)")
        }

        // Register popout hotkey (id: 2)
        let popoutShortcut = settings.popoutShortcut
        let popoutHotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 2)

        var popoutRef: EventHotKeyRef?
        let popoutStatus = RegisterEventHotKey(
            popoutShortcut.keyCode,
            popoutShortcut.modifiers,
            popoutHotKeyID,
            GetApplicationEventTarget(),
            0,
            &popoutRef
        )

        if popoutStatus == noErr {
            self.popoutHotKeyRef = popoutRef
            AppLogger.hotkeys.info("Global hotkey \(popoutShortcut.displayString, privacy: .public) registered for popout")
        } else {
            AppLogger.hotkeys.error("Failed to register popout hotkey: \(popoutStatus)")
        }

        // Register quick access hotkeys (⌥1 through ⌥5) - IDs 3-7
        if settings.quickAccessShortcutsEnabled {
            let numberKeyCodes: [UInt32] = [0x12, 0x13, 0x14, 0x15, 0x17] // 1, 2, 3, 4, 5

            for (index, keyCode) in numberKeyCodes.enumerated() {
                let quickAccessID = EventHotKeyID(signature: OSType(0x434C4950), id: UInt32(index + 3))

                var quickAccessRef: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    keyCode,
                    UInt32(optionKey),
                    quickAccessID,
                    GetApplicationEventTarget(),
                    0,
                    &quickAccessRef
                )

                if status == noErr {
                    quickAccessHotKeyRefs.append(quickAccessRef)
                    AppLogger.hotkeys.info("Quick access hotkey ⌥\(index + 1) registered")
                } else {
                    quickAccessHotKeyRefs.append(nil)
                    AppLogger.hotkeys.error("Failed to register quick access hotkey ⌥\(index + 1): \(status)")
                }
            }
        }
    }

    private func setupCaptureObserver() {
        // Observe didCapture changes to animate the icon
        Task { @MainActor in
            for await _ in clipboardService.$didCapture.values {
                updateStatusItemIcon()
            }
        }
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }

        if clipboardService.didCapture {
            button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipBoard")

            // Check if user prefers reduced motion
            let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !shouldReduceMotion {
                // Add a brief animation effect
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    button.animator().alphaValue = 0.5
                } completionHandler: {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.15
                        button.animator().alphaValue = 1.0
                    }
                }
            }
        } else {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
        }
    }

    private func triggerCaptureAnimation() {
        guard let button = statusItem.button else { return }

        // Check if user prefers reduced motion
        let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Brief fill animation for screenshot capture
        button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipBoard")

        if shouldReduceMotion {
            // Skip animation, just show filled icon briefly then reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                button.animator().alphaValue = 0.5
            } completionHandler: { [weak self] in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self?.statusItem.button?.animator().alphaValue = 1.0
                } completionHandler: {
                    // Reset to normal icon after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
                    }
                }
            }
        }
    }

    @objc func togglePopover() {
        let settings = AppSettings.shared

        // Check if using sliding panel mode (new default)
        if settings.panelModeSetting == .slidingPanel {
            ensureSlidingPanelController()
            slidingPanelController?.togglePanel()
            return
        }

        // Classic popover mode
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Refresh items before showing
                clipboardService.refreshItems()

                // Activate the app first
                NSApp.activate(ignoringOtherApps: true)

                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Make sure the popover window becomes key
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func ensureSlidingPanelController() {
        if slidingPanelController == nil {
            slidingPanelController = SlidingPanelWindowController.createShared(
                clipboardService: clipboardService,
                modelContainer: modelContainer
            )
        }
    }

    // MARK: - Popout Board

    @objc func togglePopoutBoard() {
        ensurePopoutWindowController()
        popoutWindowController?.toggleWindow()
    }

    @objc func openPopoutBoard() {
        // Close popover first if it's shown
        if popover.isShown {
            popover.performClose(nil)
        }

        // Refresh items before showing
        clipboardService.refreshItems()

        ensurePopoutWindowController()
        popoutWindowController?.showWindow()
    }

    private func ensurePopoutWindowController() {
        if popoutWindowController == nil {
            popoutWindowController = PopoutBoardWindowController.createShared(
                clipboardService: clipboardService,
                modelContainer: modelContainer
            )
        }
    }

    deinit {
        // Unregister hotkeys on cleanup
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let popoutHotKeyRef = popoutHotKeyRef {
            UnregisterEventHotKey(popoutHotKeyRef)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleClipboardPopover = Notification.Name("toggleClipboardPopover")
    static let togglePopoutBoard = Notification.Name("togglePopoutBoard")
    static let openPopoutBoard = Notification.Name("openPopoutBoard")
    static let didCopyItem = Notification.Name("didCopyItem")
    static let dismissClipboardUI = Notification.Name("dismissClipboardUI")
    static let quickAccessPaste = Notification.Name("quickAccessPaste")
}

