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
    }

    // MARK: - Permission Status

    func refreshPermissionStatus() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasFullDiskAccess = checkFullDiskAccess()

        AppLogger.clipboard.info("Permissions - Accessibility: \(self.hasAccessibilityPermission), Full Disk Access: \(self.hasFullDiskAccess)")
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)

        // Schedule a check after user might have granted permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshPermissionStatus()
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
