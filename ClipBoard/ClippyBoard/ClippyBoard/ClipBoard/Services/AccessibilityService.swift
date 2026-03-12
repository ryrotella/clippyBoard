import Foundation
import AppKit
import ApplicationServices
import os

@MainActor
class AccessibilityService: ObservableObject {
    static let shared = AccessibilityService()

    @Published private(set) var hasAccessibilityPermission: Bool = false

    private init() {
        checkAccessibilityPermission()
    }

    // MARK: - Permission Checking

    /// Check if the app has accessibility permission
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        AppLogger.hotkeys.info("Accessibility permission: \(self.hasAccessibilityPermission)")
    }

    /// Request accessibility permission (opens System Preferences)
    func requestAccessibilityPermission() {
        // This will prompt the user to grant permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted

        if !trusted {
            AppLogger.hotkeys.info("Accessibility permission prompt shown to user")
        }
    }

    // MARK: - Previous App Tracking

    /// The app that was frontmost before our UI was shown
    private(set) var previousApp: NSRunningApplication?

    /// Save the currently frontmost application (call before showing our UI)
    func savePreviousApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        // Don't save ourselves as the previous app
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
            AppLogger.hotkeys.debug("Saved previous app: \(frontmost?.localizedName ?? "nil", privacy: .public)")
        }
    }

    /// Re-activate the previously frontmost application (call before simulating paste)
    func restorePreviousApp() {
        guard let app = previousApp else {
            AppLogger.hotkeys.debug("No previous app to restore")
            return
        }
        app.activate()
        AppLogger.hotkeys.debug("Restored previous app: \(app.localizedName ?? "unknown", privacy: .public)")
        previousApp = nil
    }

    // MARK: - Paste Simulation

    /// Simulate Cmd+V paste keystroke
    /// Returns true if paste was attempted, false if permission denied
    func simulatePaste() async -> Bool {
        // Refresh permission status
        checkAccessibilityPermission()

        guard hasAccessibilityPermission else {
            AppLogger.hotkeys.warning("Cannot simulate paste: no accessibility permission")
            return false
        }

        // Small delay to ensure focus has returned to the previous app
        try? await Task.sleep(nanoseconds: 50_000_000)

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let success = self.performPasteKeyStroke()
                continuation.resume(returning: success)
            }
        }
    }

    private func performPasteKeyStroke() -> Bool {
        // Create CGEventSource
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            AppLogger.hotkeys.error("Failed to create CGEventSource")
            return false
        }

        // Key code for 'V' is 0x09
        let vKeyCode: CGKeyCode = 0x09

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            AppLogger.hotkeys.error("Failed to create key down event")
            return false
        }

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            AppLogger.hotkeys.error("Failed to create key up event")
            return false
        }

        // Set Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        AppLogger.hotkeys.debug("Simulated Cmd+V paste keystroke")
        return true
    }

    // MARK: - Simulate Specific Shortcuts

    /// Simulate any keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: CGEventFlags for modifiers (e.g., .maskCommand, .maskShift)
    func simulateKeyStroke(keyCode: CGKeyCode, modifiers: CGEventFlags) async -> Bool {
        checkAccessibilityPermission()

        guard hasAccessibilityPermission else {
            AppLogger.hotkeys.warning("Cannot simulate keystroke: no accessibility permission")
            return false
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                    continuation.resume(returning: false)
                    return
                }

                keyDown.flags = modifiers
                keyUp.flags = modifiers

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)

                continuation.resume(returning: true)
            }
        }
    }
}
