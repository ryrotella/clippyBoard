import Foundation
import AppKit
import SwiftData
import Combine

@MainActor
class ClipboardService: ObservableObject {
    @Published var isMonitoring = false
    @Published var items: [ClipboardItem] = []
    @Published var didCapture = false  // Triggers menu bar animation

    private var timer: Timer?
    private var lastChangeCount = 0
    private var modelContainer: ModelContainer?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        print("ClipboardService: ModelContainer set with schema: \(container.schema.entities.map { $0.name })")
        refreshItems()
    }

    func refreshItems() {
        guard let modelContainer = modelContainer else { return }
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            items = try context.fetch(descriptor)
            print("ClipboardService: Refreshed items, count: \(items.count)")
        } catch {
            print("ClipboardService: Failed to fetch items: \(error)")
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        lastChangeCount = NSPasteboard.general.changeCount
        isMonitoring = true

        print("ClipboardService: Started monitoring (changeCount: \(lastChangeCount))")

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
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

        print("ClipboardService: Detected clipboard change (new changeCount: \(lastChangeCount))")
        captureClipboard()
    }

    private func captureClipboard() {
        guard let modelContainer = modelContainer else {
            print("ClipboardService: No model container set")
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
            print("ClipboardService: Found \(fileURLs.count) file(s)")

            let filePaths = fileURLs.map { $0.path }
            let fileNames = fileURLs.map { $0.lastPathComponent }
            let displayText = fileNames.joined(separator: ", ")
            let searchText = fileNames.joined(separator: " ").lowercased()

            let item = ClipboardItem(
                content: filePaths.joined(separator: "\n").data(using: .utf8) ?? Data(),
                textContent: displayText,
                contentType: ContentType.file.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: displayText.count,
                searchableText: "file " + searchText
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
            return
        }

        // 2. Check for images
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            print("ClipboardService: Found image data")

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
            print("ClipboardService: Found URL: \(url)")

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
            print("ClipboardService: Found text content: \(string.prefix(50))...")

            let contentType = detectContentType(for: string)
            print("ClipboardService: Creating ClipboardItem with type: \(contentType)")
            let item = ClipboardItem(
                content: string.data(using: .utf8) ?? Data(),
                textContent: string,
                contentType: contentType.rawValue,
                sourceApp: sourceApp,
                sourceAppName: sourceAppName,
                characterCount: string.count,
                searchableText: string.lowercased()
            )

            modelContext.insert(item)
            saveAndCleanup(context: modelContext)
        }
    }

    private func detectContentType(for text: String) -> ContentType {
        // URL detection
        if let url = URL(string: text), url.scheme != nil {
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
                // If the same text was copied within the last 2 seconds, it's a duplicate
                return Date().timeIntervalSince(mostRecent.timestamp) < 2.0
            }
        } catch {
            print("Failed to check for duplicates: \(error)")
        }

        return false
    }

    private func saveAndCleanup(context: ModelContext) {
        do {
            try context.save()
            print("ClipboardService: Saved clipboard item successfully")
            enforceHistoryLimit(context: context)
            refreshItems()
            triggerCaptureAnimation()
        } catch {
            print("ClipboardService: Failed to save clipboard item: \(error)")
        }
    }

    private func triggerCaptureAnimation() {
        didCapture = true
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
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
            print("Failed to enforce history limit: \(error)")
        }
    }

    // MARK: - Public Actions

    func copyToClipboard(_ item: ClipboardItem) {
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
            if let path = item.textContent {
                pasteboard.setString(path, forType: .string)
            }
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
            print("Failed to clear history: \(error)")
        }
    }

    func copyTransformedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
