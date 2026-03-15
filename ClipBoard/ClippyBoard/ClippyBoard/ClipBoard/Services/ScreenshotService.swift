import Foundation
import AppKit
import SwiftData
import Vision
import os

@MainActor
class ScreenshotService: ObservableObject {
    @Published var isMonitoring = false
    @Published var lastScreenshotDate: Date?

    private var query: NSMetadataQuery?
    private var modelContainer: ModelContainer?
    private var processedScreenshots: Set<String> = []  // Track processed files to avoid duplicates
    private let bookmarkManager = SecurityScopedBookmarkManager.shared

    // Directory watcher for synced files (e.g. phone screenshots via iCloud)
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif", "webp"]

    var onScreenshotCaptured: (() -> Void)?

    init() {
        // Listen for screenshots folder changes to restart monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFolderChange),
            name: .screenshotsFolderDidChange,
            object: nil
        )
    }

    @objc private func handleFolderChange() {
        AppLogger.screenshot.info("Screenshots folder changed, restarting monitoring")
        stopMonitoring()
        startMonitoring()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    /// Check if screenshot monitoring is available (has folder access)
    var canMonitorScreenshots: Bool {
        bookmarkManager.hasScreenshotsFolderAccess
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Check if we have folder access
        if !bookmarkManager.hasScreenshotsFolderAccess {
            AppLogger.screenshot.info("Screenshot monitoring disabled - no folder access. User needs to select Screenshots folder in Settings.")
            return
        }

        // Snapshot existing files so we don't re-import them
        snapshotExistingImages()

        // Start Spotlight query for native macOS screenshots
        startMetadataQuery()

        // Start directory watcher for synced files (phone screenshots)
        startDirectoryWatcher()

        isMonitoring = true
        AppLogger.screenshot.info("Started monitoring for screenshots and synced images")
    }

    func stopMonitoring() {
        // Stop Spotlight query
        query?.stop()
        query = nil

        // Stop directory watcher
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1

        isMonitoring = false

        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: nil)
    }

    // MARK: - Snapshot existing files

    private func snapshotExistingImages() {
        guard let folderURL = bookmarkManager.screenshotsFolderURL else { return }

        do {
            let contents = try bookmarkManager.contentsOfDirectory(at: folderURL)
            for fileURL in contents {
                if Self.imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                    processedScreenshots.insert(fileURL.path)
                }
            }
            AppLogger.screenshot.info("Snapshot complete, found \(self.processedScreenshots.count) existing images")
        } catch {
            AppLogger.screenshot.warning("Failed to snapshot directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Spotlight metadata query (native macOS screenshots)

    private func startMetadataQuery() {
        query = NSMetadataQuery()
        guard let query = query else { return }

        // Search for native macOS screenshots only via Spotlight
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")

        if let folderURL = bookmarkManager.screenshotsFolderURL {
            query.searchScopes = [folderURL]
        } else {
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
        }

        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: false)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        let started = query.start()
        AppLogger.screenshot.info("Spotlight query started: \(started)")

        if !started {
            AppLogger.screenshot.error("Failed to start Spotlight query - check Full Disk Access permissions")
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        query?.disableUpdates()

        // Record existing screenshots so we don't import old ones
        if let query = query {
            for i in 0..<query.resultCount {
                if let item = query.result(at: i) as? NSMetadataItem,
                   let path = item.value(forAttribute: kMDItemPath as String) as? String {
                    processedScreenshots.insert(path)
                }
            }
        }

        AppLogger.screenshot.info("Spotlight gather complete, tracking \(self.processedScreenshots.count) existing files")
        query?.enableUpdates()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        query?.disableUpdates()

        guard let userInfo = notification.userInfo,
              let addedItems = userInfo[kMDQueryUpdateAddedItems] as? [NSMetadataItem] else {
            query?.enableUpdates()
            return
        }

        for item in addedItems {
            processMetadataItem(item)
        }

        query?.enableUpdates()
    }

    private func processMetadataItem(_ item: NSMetadataItem) {
        guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { return }

        // Skip if already processed
        guard !processedScreenshots.contains(path) else { return }
        processedScreenshots.insert(path)

        let creationDate = item.value(forAttribute: kMDItemFSCreationDate as String) as? Date ?? Date()

        // Only process screenshots from the last 30 seconds (avoid old ones on restart)
        guard Date().timeIntervalSince(creationDate) < 30 else {
            AppLogger.screenshot.debug("Skipping old screenshot via Spotlight")
            return
        }

        AppLogger.screenshot.info("New native screenshot detected: \(path, privacy: .public)")

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await loadAndProcessScreenshot(path: path, creationDate: creationDate, isNativeScreenshot: true)
        }
    }

    // MARK: - Directory watcher (synced files like phone screenshots)

    private func startDirectoryWatcher() {
        guard let folderURL = bookmarkManager.screenshotsFolderURL else { return }

        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else {
            AppLogger.screenshot.error("Failed to open directory for watching: \(folderURL.path, privacy: .public)")
            return
        }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scanForNewImages()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directorySource = source
        AppLogger.screenshot.info("Directory watcher started for: \(folderURL.path, privacy: .public)")
    }

    private func scanForNewImages() {
        guard let folderURL = bookmarkManager.screenshotsFolderURL else { return }

        do {
            let contents = try bookmarkManager.contentsOfDirectory(at: folderURL)
            for fileURL in contents {
                let path = fileURL.path
                let ext = fileURL.pathExtension.lowercased()

                guard Self.imageExtensions.contains(ext) else { continue }
                guard !processedScreenshots.contains(path) else { continue }
                processedScreenshots.insert(path)

                AppLogger.screenshot.info("New synced image detected: \(path, privacy: .public)")

                Task {
                    // Wait for the file to finish syncing/writing
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    await loadAndProcessScreenshot(path: path, creationDate: Date(), isNativeScreenshot: false)
                }
            }
        } catch {
            AppLogger.screenshot.warning("Failed to scan directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Shared processing

    private func loadAndProcessScreenshot(path: String, creationDate: Date, isNativeScreenshot: Bool = true) async {
        // Check if this path is in our authorized folder
        guard bookmarkManager.isPathAuthorized(path) else {
            AppLogger.screenshot.debug("Screenshot not in authorized folder, skipping: \(path, privacy: .public)")
            return
        }

        // Debug: Check file accessibility
        AppLogger.screenshot.debug("Checking file accessibility with security-scoped bookmark")

        // Try reading file data using the security-scoped bookmark
        var imageData: Data?
        for attempt in 1...3 {
            do {
                imageData = try bookmarkManager.readFileData(at: path)
                if imageData != nil { break }
            } catch {
                AppLogger.screenshot.warning("Retry \(attempt) - Error: \(error.localizedDescription, privacy: .public)")
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        guard let data = imageData, let image = NSImage(data: data) else {
            AppLogger.screenshot.error("Failed to load screenshot image after retries")
            return
        }

        // Convert to PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            AppLogger.screenshot.error("Failed to convert image to PNG")
            return
        }

        AppLogger.screenshot.debug("Successfully loaded image (\(pngData.count) bytes), running OCR...")

        // Run OCR
        let extractedText = await performOCR(on: image)
        await saveScreenshot(
            imageData: pngData,
            extractedText: extractedText,
            sourcePath: path,
            timestamp: creationDate,
            isNativeScreenshot: isNativeScreenshot
        )
    }

    private func performOCR(on image: NSImage) async -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLogger.screenshot.error("OCR failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: "")
            }
        }
    }

    @MainActor
    private func saveScreenshot(imageData: Data, extractedText: String, sourcePath: String, timestamp: Date, isNativeScreenshot: Bool = true) async {
        guard let modelContainer = modelContainer else {
            AppLogger.screenshot.warning("No model container")
            return
        }

        let context = modelContainer.mainContext

        // Create searchable text combining "screenshot" and any OCR text
        var searchableText = "screenshot"
        if !extractedText.isEmpty {
            searchableText += " " + extractedText.lowercased()
        }

        let item = ClipboardItem(
            content: imageData,
            textContent: extractedText.isEmpty ? nil : extractedText,
            contentType: ContentType.image.rawValue,
            timestamp: timestamp,
            sourceApp: isNativeScreenshot ? "com.apple.screencaptureui" : "com.apple.shortcuts",
            sourceAppName: isNativeScreenshot ? "Screenshot" : "Phone Screenshot",
            searchableText: searchableText
        )

        context.insert(item)

        do {
            try context.save()
            AppLogger.screenshot.info("Saved screenshot with \(extractedText.count) chars of OCR text")
            lastScreenshotDate = timestamp
            onScreenshotCaptured?()
        } catch {
            AppLogger.screenshot.error("Failed to save screenshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
