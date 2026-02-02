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

    var onScreenshotCaptured: (() -> Void)?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        query = NSMetadataQuery()
        guard let query = query else { return }

        // Search for screenshots using Spotlight metadata
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]

        // Sort by creation date, newest first
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: false)]

        // Observe for new results
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
        isMonitoring = started
        AppLogger.screenshot.info("Started monitoring for screenshots: \(started)")

        if !started {
            AppLogger.screenshot.error("Failed to start query - check Full Disk Access permissions")
        }
    }

    func stopMonitoring() {
        query?.stop()
        query = nil
        isMonitoring = false

        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: nil)
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        query?.disableUpdates()

        // On initial gather, just record existing screenshots so we don't import old ones
        if let query = query {
            for i in 0..<query.resultCount {
                if let item = query.result(at: i) as? NSMetadataItem,
                   let path = item.value(forAttribute: kMDItemPath as String) as? String {
                    processedScreenshots.insert(path)
                }
            }
        }

        AppLogger.screenshot.info("Initial gather complete, found \(self.processedScreenshots.count) existing screenshots")
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
            processScreenshot(item)
        }

        query?.enableUpdates()
    }

    private func processScreenshot(_ item: NSMetadataItem) {
        guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { return }

        // Skip if already processed
        guard !processedScreenshots.contains(path) else { return }
        processedScreenshots.insert(path)

        // Get creation date
        let creationDate = item.value(forAttribute: kMDItemFSCreationDate as String) as? Date ?? Date()

        // Only process screenshots from the last 30 seconds (avoid old ones on restart)
        guard Date().timeIntervalSince(creationDate) < 30 else {
            AppLogger.screenshot.debug("Skipping old screenshot")
            return
        }

        AppLogger.screenshot.info("New screenshot detected")

        // Wait a moment for macOS to finish writing the file
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await loadAndProcessScreenshot(path: path, creationDate: creationDate)
        }
    }

    private func loadAndProcessScreenshot(path: String, creationDate: Date) async {
        let url = URL(fileURLWithPath: path)

        // Debug: Check file accessibility
        AppLogger.screenshot.debug("Checking file accessibility")

        // Try reading file data directly
        var imageData: Data?
        for attempt in 1...3 {
            do {
                imageData = try Data(contentsOf: url)
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
            timestamp: creationDate
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
    private func saveScreenshot(imageData: Data, extractedText: String, sourcePath: String, timestamp: Date) async {
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
            sourceApp: "com.apple.screencaptureui",
            sourceAppName: "Screenshot",
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
