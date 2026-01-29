import AppKit
import SwiftUI
import SwiftData
import Carbon

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var clipboardService: ClipboardService!
    private var screenshotService: ScreenshotService!
    private var modelContainer: ModelContainer!
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Setup status bar item
        setupStatusItem()

        // Setup popover
        setupPopover()

        // Setup global hotkey
        setupHotkey()

        // Observe capture events to animate icon
        setupCaptureObserver()

        // Observe hotkey notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePopover),
            name: .toggleClipboardPopover,
            object: nil
        )
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
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Ensure default pinboard exists
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
            print("Failed to ensure default pinboard: \(error)")
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
            button.action = #selector(togglePopover)
            button.target = self
        }
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

    private func setupHotkey() {
        // Register ⌘⇧V globally using Carbon API
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 1) // "CLIP"

        // V key = 0x09, Command = cmdKey, Shift = shiftKey
        let keyCode: UInt32 = 0x09 // V key
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install event handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                // Post notification to toggle popover
                NotificationCenter.default.post(name: .toggleClipboardPopover, object: nil)
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            self.hotKeyRef = hotKeyRef
            print("Global hotkey ⌘⇧V registered successfully")
        } else {
            print("Failed to register global hotkey: \(status)")
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
        } else {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")
        }
    }

    private func triggerCaptureAnimation() {
        guard let button = statusItem.button else { return }

        // Brief fill animation for screenshot capture
        button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipBoard")

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

    @objc func togglePopover() {
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

    deinit {
        // Unregister hotkey on cleanup
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleClipboardPopover = Notification.Name("toggleClipboardPopover")
}

