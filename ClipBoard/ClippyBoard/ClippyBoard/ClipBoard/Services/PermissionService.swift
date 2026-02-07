import Foundation
import AppKit
import ApplicationServices
import os

@MainActor
class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var hasFullDiskAccess: Bool = false

    private init() {
        refreshPermissionStatus()

        // Refresh permissions when app becomes active (user returns from System Settings)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
            }
        }
    }

    // MARK: - Permission Status

    func refreshPermissionStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasFullDiskAccess = checkFullDiskAccess()

        // Log bundle ID to help debug permission issues
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        AppLogger.clipboard.info("Permissions - Accessibility: \(self.hasAccessibilityPermission), Bundle: \(bundleID, privacy: .public)")
    }

    private func checkFullDiskAccess() -> Bool {
        // Try to read the Screenshots folder to check Full Disk Access
        let screenshotsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")

        do {
            _ = try FileManager.default.contentsOfDirectory(at: screenshotsPath, includingPropertiesForKeys: nil)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Request Permissions

    func requestAccessibilityPermission() {
        // For sandboxed apps, AXIsProcessTrustedWithOptions prompt doesn't work reliably
        // Open System Settings directly instead
        openAccessibilitySettings()

        // Schedule periodic checks after user might have granted permission
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshPermissionStatus()
            }
        }
    }

    func openFullDiskAccessSettings() {
        // Try the modern URL scheme first (macOS 13+), fall back to legacy
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func openAccessibilitySettings() {
        // Try the modern URL scheme first (macOS 13+), fall back to legacy
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Feature Availability

    /// Whether click-to-paste feature is available
    var canUsePasteFeature: Bool {
        hasAccessibilityPermission
    }

    /// Whether screenshot capture is available
    var canCaptureScreenshots: Bool {
        hasFullDiskAccess
    }
}
