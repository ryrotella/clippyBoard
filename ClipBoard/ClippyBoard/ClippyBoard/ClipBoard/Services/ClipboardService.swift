import Foundation
import AppKit
import SwiftData
import Combine
import os

@MainActor
class ClipboardService: ObservableObject {
    // MARK: - Constants

    private enum Constants {
        /// Interval for polling clipboard changes
        static let pollingInterval: TimeInterval = 0.5
        /// Time threshold for detecting duplicate clipboard entries
        static let duplicateThresholdSeconds: TimeInterval = 2.0
        /// Duration of the capture animation in nanoseconds
        static let captureAnimationDuration: UInt64 = 300_000_000
    }

    // MARK: - Published Properties

    @Published var isMonitoring = false
    @Published var items: [ClipboardItem] = []
    @Published var didCapture = false  // Triggers menu bar animation

    // MARK: - Private Properties

    private var timer: Timer?
    private var lastChangeCount = 0
    private var modelContainer: ModelContainer?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        AppLogger.clipboard.info("ModelContainer set with schema: \(container.schema.entities.map { $0.name }, privacy: .public)")
        refreshItems()
        performAutoClear()
    }

    func refreshItems() {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            items = try context.fetch(descriptor)
            AppLogger.clipboard.debug("Refreshed items, count: \(self.items.count)")
        } catch {
            AppLogger.clipboard.error("Failed to fetch items: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        lastChangeCount = NSPasteboard.general.changeCount
        isMonitoring = true

        AppLogger.clipboard.info("Started monitoring (changeCount: \(self.lastChangeCount))")

        timer = Timer.scheduledTimer(withTimeInterval: Constants.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
        // Add timer to common run loop mode so it runs during menu tracking
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        AppLogger.clipboard.debug("Detected clipboard change (new changeCount: \(self.lastChangeCount))")
        captureClipboard()
    }

    private func captureClipboard() {
        guard let modelContainer = modelContainer else {
            AppLogger.clipboard.warning("No model container set")
            return
        }

        let modelContext = modelContainer.mainContext
        let pasteboard = NSPasteboard.general

        // Get active app info
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let sourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check if app is excluded
        if AppSettings.shared.isAppExcluded(sourceApp) {
            return
        }

        // Check incognito mode
        if AppSettings.shared.incognitoMode {
            return
        }

        // Determine content type and extract content
        // Check order matters: files first, then images, then URLs, then text

        // 1. Check for files (copied from Finder)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            AppLogger.clipboard.debug("Found \(fileURLs.count) file(s)")

            let filePaths = fileURLs.map { $0.path }
            let fileNames = fileURLs.map { $0.lastPathComponent }
            let displayText = fileNames.joined(separator: ", ")
            let searchText = fileNames.joined(separator: " ").lowercased()

            // Generate thumbnail if it's an image file
            var thumbnailData: Data?
            if let firstURL = fileURLs.first, ThumbnailGenerator.isImageFile(firstURL) {
                thumbnailData = ThumbnailGenerator.generateThumbnail(for: firstURL)
                if thumbnailData != nil {
                    AppLogger.clipboard.debug("Generated thumbnail for image file")
                }
            }

            let item = ClipboardItem(
                content: filePaths.joined(separator: "\n").data(using: .utf8) ?? Data(),
                textContent: displayText,
                contentType: ContentType.file.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: displayText.count,
                searchableText: "file " + searchText,
                thumbnailData: thumbnailData
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 2. Check for images
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            AppLogger.clipboard.debug("Found image data")

            let item = ClipboardItem(
                content: imageData,
                contentType: ContentType.image.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                searchableText: "image"
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 3. Check for URLs (web links, not file URLs)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL],
           let url = urls.first,
           !url.isFileURL {
            AppLogger.clipboard.debug("Found URL")

            let urlString = url.absoluteString
            let item = ClipboardItem(
                content: urlString.data(using: .utf8) ?? Data(),
                textContent: urlString,
                contentType: ContentType.url.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: urlString.count,
                searchableText: urlString.lowercased()
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 4. Check for text (last, as other types may also have text representations)
        if let string = pasteboard.string(forType: .string) {
            AppLogger.clipboard.debug("Found text content (\(string.count) chars)")

            // Check for duplicates before inserting
            if isDuplicate(text: string, in: modelContext) {
                AppLogger.clipboard.debug("Skipping duplicate text content")
                return
            }

            // Detect sensitive content (passwords, API keys, tokens) if protection is enabled
            let isSensitive = AppSettings.shared.sensitiveContentProtection && SensitiveContentDetector.isSensitive(string)
            if isSensitive {
                AppLogger.clipboard.info("Detected sensitive content (API key, token, or password)")
            }

            let contentType = detectContentType(for: string)
            AppLogger.clipboard.debug("Creating ClipboardItem with type: \(contentType.rawValue, privacy: .public)")
            let item = ClipboardItem(
                content: string.data(using: .utf8) ?? Data(),
                textContent: string,
                contentType: contentType.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: string.count,
                searchableText: string.lowercased(),
                isSensitive: isSensitive
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
        }
    }

    /// Safe URL schemes that are allowed
    private static let safeURLSchemes: Set<String> = ["http", "https", "mailto", "tel", "file"]

    private func detectContentType(for text: String) -> ContentType {
        // URL detection with scheme validation
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           Self.safeURLSchemes.contains(scheme) {
            return .url
        }

        // Email detection
        let emailPattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        if text.range(of: emailPattern, options: .regularExpression) != nil {
            return .url // Treat emails as URLs for now
        }

        return .text
    }

    private func isDuplicate(text: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.textContent == text },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let existing = try context.fetch(descriptor)
            if let mostRecent = existing.first {
                // If the same text was copied within the threshold, it's a duplicate
                return Date().timeIntervalSince(mostRecent.timestamp) < Constants.duplicateThresholdSeconds
            }
        } catch {
            AppLogger.clipboard.error("Failed to check for duplicates: \(error.localizedDescription, privacy: .public)")
        }

        return false
    }

    private func saveAndCleanup(context: ModelContext) {
        do {
            try context.save()
            AppLogger.clipboard.debug("Saved clipboard item successfully")
            enforceHistoryLimit(context: context)
            refreshItems()
            triggerCaptureAnimation()
        } catch {
            AppLogger.clipboard.error("Failed to save clipboard item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func triggerCaptureAnimation() {
        didCapture = true
        Task {
            try? await Task.sleep(nanoseconds: Constants.captureAnimationDuration)
            didCapture = false
        }
    }

    private func enforceHistoryLimit(context: ModelContext) {
        let limit = AppSettings.shared.historyLimit

        // Only delete non-pinned items beyond the limit
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let items = try context.fetch(descriptor)
            if items.count > limit {
                for item in items.dropFirst(limit) {
                    context.delete(item)
                }
                try context.save()
            }
        } catch {
            AppLogger.clipboard.error("Failed to enforce history limit: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes non-pinned items older than the configured auto-clear threshold
    private func performAutoClear() {
        let autoClearDays = AppSettings.shared.autoClearDays
        guard autoClearDays > 0 else { return } // 0 = never auto-clear

        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -autoClearDays, to: Date()) ?? Date()

        // Delete non-pinned items older than cutoff date
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned == false && $0.timestamp < cutoffDate }
        )

        do {
            let oldItems = try context.fetch(descriptor)
            guard !oldItems.isEmpty else { return }

            for item in oldItems {
                context.delete(item)
            }
            try context.save()
            AppLogger.clipboard.info("Auto-cleared \(oldItems.count) items older than \(autoClearDays) days")
            refreshItems()
        } catch {
            AppLogger.clipboard.error("Failed to auto-clear old items: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public Actions

    /// Copies an item to the clipboard (without authentication check)
    /// For sensitive items, use `copyToClipboardWithAuth` instead
    func copyToClipboard(_ item: ClipboardItem) {
        performCopy(item)
    }

    /// Copies an item to the clipboard, requiring authentication for sensitive items
    /// - Returns: True if the copy succeeded, false if authentication failed or was cancelled
    func copyToClipboardWithAuth(_ item: ClipboardItem) async -> Bool {
        if item.isSensitive {
            let authenticated = await AuthenticationService.shared.authenticate(
                for: item.id,
                reason: "Authenticate to copy sensitive content"
            )
            guard authenticated else {
                AppLogger.clipboard.info("Copy cancelled - authentication failed for sensitive item")
                return false
            }
        }

        performCopy(item)
        return true
    }

    /// Internal method to perform the actual copy
    private func performCopy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentTypeEnum {
        case .text, .url:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            pasteboard.setData(item.content, forType: .png)
        case .file:
            copyFileItem(item, to: pasteboard)
        }
    }

    /// Copies a file item to the pasteboard, with special handling for image files
    private func copyFileItem(_ item: ClipboardItem, to pasteboard: NSPasteboard) {
        guard let pathsString = String(data: item.content, encoding: .utf8) else {
            return
        }

        let paths = pathsString.components(separatedBy: "\n")
        let urls = paths.compactMap { URL(fileURLWithPath: $0) }

        guard let firstURL = urls.first else {
            // Fallback: just paste the filename
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
            return
        }

        // Check if it's an image file
        if ThumbnailGenerator.isImageFile(firstURL) {
            // For image files: paste the image data so it can be pasted as an image
            if let imageData = try? Data(contentsOf: firstURL) {
                // Determine the image type and set appropriate pasteboard type
                let ext = firstURL.pathExtension.lowercased()

                // Put image data on pasteboard
                if ext == "png" {
                    pasteboard.setData(imageData, forType: .png)
                } else if ext == "tiff" || ext == "tif" {
                    pasteboard.setData(imageData, forType: .tiff)
                } else {
                    // For other formats (jpg, heic, etc.), convert to PNG for compatibility
                    if let nsImage = NSImage(data: imageData),
                       let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                }

                // Also add the file URL so apps that want the file can use it
                pasteboard.writeObjects([firstURL as NSURL])

                // Add filename as string for apps that want text
                pasteboard.setString(firstURL.lastPathComponent, forType: .string)

                AppLogger.clipboard.debug("Copied image file with image data, URL, and filename")
                return
            }
        }

        // For non-image files: paste as file URLs
        pasteboard.writeObjects(urls as [NSURL])

        // Also add the filename(s) as string
        if let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext
        context.delete(item)
        try? context.save()
        refreshItems()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext
        item.isPinned.toggle()
        try? context.save()
        refreshItems()
    }

    func clearHistory(keepPinned: Bool = true) {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext

        let predicate: Predicate<ClipboardItem>? = keepPinned
            ? #Predicate { $0.isPinned == false }
            : nil

        let descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)

        do {
            let items = try context.fetch(descriptor)
            for item in items {
                context.delete(item)
            }
            try context.save()
            refreshItems()
        } catch {
            AppLogger.clipboard.error("Failed to clear history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func copyTransformedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
