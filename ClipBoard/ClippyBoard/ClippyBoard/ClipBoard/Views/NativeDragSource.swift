import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// View modifier that enables native AppKit drag and drop for maximum cross-app compatibility,
/// and handles single/double click directly (avoiding SwiftUI `.onTapGesture` conflicts with `.contextMenu`).
struct NativeDragModifier: ViewModifier {
    let contentType: ContentType
    let contentData: Data
    let textContent: String?
    let allFilePaths: [String]
    let canDrag: Bool
    let onSingleClick: (() -> Void)?
    let onDoubleClick: (() -> Void)?

    @MainActor
    init(item: ClipboardItem,
         canDrag: Bool = true,
         onSingleClick: (() -> Void)? = nil,
         onDoubleClick: (() -> Void)? = nil) {
        self.contentType = item.contentTypeEnum
        self.contentData = item.content
        self.textContent = item.textContent
        self.canDrag = canDrag
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        if item.contentTypeEnum == .file,
           let pathsString = String(data: item.content, encoding: .utf8) {
            self.allFilePaths = pathsString.components(separatedBy: "\n").filter { !$0.isEmpty }
        } else {
            self.allFilePaths = []
        }
    }

    func body(content: Content) -> some View {
        content.overlay(
            DragSourceRepresentable(
                contentType: contentType,
                contentData: contentData,
                textContent: textContent,
                allFilePaths: allFilePaths,
                canDrag: canDrag,
                onSingleClick: onSingleClick,
                onDoubleClick: onDoubleClick
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

// MARK: - NSViewRepresentable Bridge

private struct DragSourceRepresentable: NSViewRepresentable {
    let contentType: ContentType
    let contentData: Data
    let textContent: String?
    let allFilePaths: [String]
    let canDrag: Bool
    let onSingleClick: (() -> Void)?
    let onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        updateViewData(view)
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        updateViewData(nsView)
    }

    private func updateViewData(_ view: DragSourceNSView) {
        view.contentType = contentType
        view.contentData = contentData
        view.textContent = textContent
        view.allFilePaths = allFilePaths
        view.canDrag = canDrag
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
    }
}

// MARK: - Native Drag Source NSView

/// Transparent NSView overlay that:
/// - Intercepts left-click drags to initiate AppKit dragging sessions
/// - Handles single/double click directly via closures (no SwiftUI tap gesture conflicts)
/// - Forwards right-click and scroll events to the responder chain
class DragSourceNSView: NSView, NSDraggingSource {
    var contentType: ContentType = .text
    var contentData = Data()
    var textContent: String?
    var allFilePaths: [String] = []
    var canDrag: Bool = true
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var tempFileURLs: [URL] = []
    private var pendingSingleClick: DispatchWorkItem?
    private let dragThreshold: CGFloat = 4.0

    /// When true, all DragSourceNSView instances become invisible to hit testing.
    /// Used so that right-click and context menu events reach SwiftUI underneath.
    private static var isPassingThrough = false

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        if DragSourceNSView.isPassingThrough { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        // Cancel pending single-click if this is a second click (double-click)
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent else { return }
        // Only initiate drag from a single-click, not double-click
        guard downEvent.clickCount == 1 else { return }
        // Block drag for sensitive unrevealed items
        guard canDrag else { return }

        let start = convert(downEvent.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)

        if distance > dragThreshold {
            let savedEvent = downEvent
            mouseDownEvent = nil
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            startDrag(with: savedEvent)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil

        if event.clickCount >= 2 {
            // Double-click: fire immediately
            onDoubleClick?()
        } else {
            // Single-click: delay to allow double-click detection
            let work = DispatchWorkItem { [weak self] in
                self?.onSingleClick?()
            }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval,
                execute: work
            )
        }
    }

    // Forward right-click to SwiftUI for context menu
    override func rightMouseDown(with event: NSEvent) {
        // Become invisible so the right-click reaches SwiftUI's .contextMenu
        DragSourceNSView.isPassingThrough = true
        defer { DragSourceNSView.isPassingThrough = false }

        if let target = window?.contentView?.hitTest(event.locationInWindow) {
            target.rightMouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        // Clean up temp files after giving the receiving app time to read
        let filesToClean = tempFileURLs
        tempFileURLs = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            for url in filesToClean {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Drag Session Creation

    private func startDrag(with mouseDownEvent: NSEvent) {
        let items = createDraggingItems()
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: mouseDownEvent, source: self)
    }

    private func createDraggingItems() -> [NSDraggingItem] {
        let dragImage = createDragImage()

        switch contentType {
        case .text:
            guard let text = textContent, !text.isEmpty else { return [] }
            return [makeDraggingItem(image: dragImage) { pbItem in
                pbItem.setString(text, forType: .string)
            }]

        case .url:
            guard let text = textContent, !text.isEmpty else { return [] }
            return [makeDraggingItem(image: dragImage) { pbItem in
                pbItem.setString(text, forType: .URL)
                pbItem.setString(text, forType: .string)
            }]

        case .image:
            return [makeDraggingItem(image: dragImage) { pbItem in
                // Convert to PNG (contentData could be TIFF)
                var pngData = self.contentData
                if let nsImage = NSImage(data: self.contentData),
                   let tiffRep = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffRep),
                   let converted = bitmap.representation(using: .png, properties: [:]) {
                    pngData = converted
                }

                // Raw image data for apps that accept pasteboard image data
                pbItem.setData(pngData, forType: .png)
                if let nsImage = NSImage(data: self.contentData),
                   let tiffData = nsImage.tiffRepresentation {
                    pbItem.setData(tiffData, forType: .tiff)
                }

                // Temp file for apps that prefer file-based drops (Figma, Electron, etc.)
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".png")
                if (try? pngData.write(to: tempFile)) != nil {
                    self.tempFileURLs.append(tempFile)
                    pbItem.setString(tempFile.absoluteString, forType: .fileURL)
                }
            }]

        case .file:
            guard !allFilePaths.isEmpty else { return [] }
            return allFilePaths.compactMap { path in
                makeDraggingItem(image: dragImage) { pbItem in
                    // Always provide path as text (works for text-accepting apps)
                    pbItem.setString(path, forType: .string)

                    // If the file is readable, copy to temp dir to avoid sandbox extension issues
                    if FileManager.default.isReadableFile(atPath: path) {
                        let tempDir = FileManager.default.temporaryDirectory
                        let fileName = (path as NSString).lastPathComponent
                        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + "_" + fileName)
                        if (try? FileManager.default.copyItem(
                            at: URL(fileURLWithPath: path),
                            to: tempFile
                        )) != nil {
                            self.tempFileURLs.append(tempFile)
                            pbItem.setString(tempFile.absoluteString, forType: .fileURL)
                        }
                    }
                }
            }
        }
    }

    private func makeDraggingItem(image: NSImage,
                                  populate: (NSPasteboardItem) -> Void) -> NSDraggingItem {
        let pbItem = NSPasteboardItem()
        populate(pbItem)
        let item = NSDraggingItem(pasteboardWriter: pbItem)
        item.setDraggingFrame(bounds, contents: image)
        return item
    }

    // MARK: - Drag Preview Image

    private func createDragImage() -> NSImage {
        let width = max(bounds.width, 120)
        let height: CGFloat = 48
        let size = NSSize(width: min(width, 260), height: height)

        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlBackgroundColor.withAlphaComponent(0.9).set()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

            NSColor.separatorColor.withAlphaComponent(0.5).set()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

            let label: String
            switch self.contentType {
            case .text: label = String((self.textContent ?? "Text").prefix(40))
            case .url: label = String((self.textContent ?? "URL").prefix(40))
            case .image: label = "Image"
            case .file:
                label = self.allFilePaths.first?
                    .components(separatedBy: "/").last ?? "File"
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let textRect = rect.insetBy(dx: 12, dy: (rect.height - 16) / 2)
            label.draw(in: textRect, withAttributes: attrs)

            return true
        }
    }
}

// MARK: - View Extension

extension View {
    /// Enables native AppKit drag and drop with integrated click handling.
    /// Use this INSTEAD of `.onTapGesture` to avoid conflicts with `.contextMenu`.
    /// Set `canDrag: false` to block dragging (e.g. for sensitive unrevealed items).
    @MainActor
    func nativeDraggable(item: ClipboardItem,
                         canDrag: Bool = true,
                         onSingleClick: (() -> Void)? = nil,
                         onDoubleClick: (() -> Void)? = nil) -> some View {
        modifier(NativeDragModifier(item: item,
                                    canDrag: canDrag,
                                    onSingleClick: onSingleClick,
                                    onDoubleClick: onDoubleClick))
    }
}
