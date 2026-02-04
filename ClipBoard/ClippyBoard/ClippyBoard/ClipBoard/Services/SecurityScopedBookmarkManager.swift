import Foundation
import AppKit
import os.log

/// Notification posted when screenshots folder access changes
extension Notification.Name {
    static let screenshotsFolderDidChange = Notification.Name("screenshotsFolderDidChange")
}

/// Manages security-scoped bookmarks for sandbox file access
@MainActor
class SecurityScopedBookmarkManager: ObservableObject {
    static let shared = SecurityScopedBookmarkManager()

    @Published private(set) var screenshotsFolderURL: URL?
    @Published private(set) var hasScreenshotsFolderAccess: Bool = false

    private let bookmarkKey = "screenshotsFolderBookmark"
    private var accessingSecurityScopedResource = false

    private init() {
        loadBookmark()
    }

    // MARK: - Public Methods

    /// Prompts user to select the Screenshots folder
    func selectScreenshotsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Screenshots Folder"
        panel.message = "Choose the folder where macOS saves your screenshots (usually Desktop or a Screenshots folder)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Try to start in the likely screenshots location
        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktopURL
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self?.saveBookmark(for: url)
            }
        }
    }

    /// Clears the saved bookmark
    func clearScreenshotsFolder() {
        stopAccessingFolder()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        screenshotsFolderURL = nil
        hasScreenshotsFolderAccess = false
        AppLogger.screenshot.info("Cleared screenshots folder bookmark")
    }

    /// Call this before accessing files in the screenshots folder
    func startAccessingFolder() -> Bool {
        guard let url = screenshotsFolderURL, !accessingSecurityScopedResource else {
            return hasScreenshotsFolderAccess
        }

        accessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        hasScreenshotsFolderAccess = accessingSecurityScopedResource

        if accessingSecurityScopedResource {
            AppLogger.screenshot.debug("Started accessing security-scoped resource")
        } else {
            AppLogger.screenshot.warning("Failed to start accessing security-scoped resource")
        }

        return accessingSecurityScopedResource
    }

    /// Call this when done accessing files
    func stopAccessingFolder() {
        guard accessingSecurityScopedResource, let url = screenshotsFolderURL else { return }

        url.stopAccessingSecurityScopedResource()
        accessingSecurityScopedResource = false
        AppLogger.screenshot.debug("Stopped accessing security-scoped resource")
    }

    /// Check if a file path is within the authorized screenshots folder
    func isPathAuthorized(_ path: String) -> Bool {
        guard let folderURL = screenshotsFolderURL else { return false }
        let fileURL = URL(fileURLWithPath: path)
        return fileURL.path.hasPrefix(folderURL.path)
    }

    /// Read file data with security-scoped access
    func readFileData(at path: String) throws -> Data {
        guard isPathAuthorized(path) else {
            throw NSError(
                domain: "SecurityScopedBookmarkManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File is not in authorized folder"]
            )
        }

        guard startAccessingFolder() else {
            throw NSError(
                domain: "SecurityScopedBookmarkManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access security-scoped resource"]
            )
        }

        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
    }

    // MARK: - Private Methods

    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            screenshotsFolderURL = url
            hasScreenshotsFolderAccess = true

            // Start accessing immediately
            _ = startAccessingFolder()

            AppLogger.screenshot.info("Saved screenshots folder bookmark: \(url.path, privacy: .public)")

            // Notify that folder access changed so ScreenshotService can start monitoring
            NotificationCenter.default.post(name: .screenshotsFolderDidChange, object: nil)
        } catch {
            AppLogger.screenshot.error("Failed to create bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            AppLogger.screenshot.debug("No screenshots folder bookmark found")
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                AppLogger.screenshot.warning("Bookmark is stale, need to re-select folder")
                // Try to refresh the bookmark
                saveBookmark(for: url)
            } else {
                screenshotsFolderURL = url
                hasScreenshotsFolderAccess = true
                _ = startAccessingFolder()
                AppLogger.screenshot.info("Loaded screenshots folder bookmark: \(url.path, privacy: .public)")
            }
        } catch {
            AppLogger.screenshot.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }
}
