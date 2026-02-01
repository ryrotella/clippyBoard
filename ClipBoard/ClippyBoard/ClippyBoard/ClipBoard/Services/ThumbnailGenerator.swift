import AppKit
import QuickLookThumbnailing

/// Generates thumbnails for files, particularly image files
enum ThumbnailGenerator {

    /// Image file extensions that we can generate thumbnails for
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
        "heic", "heif", "webp", "ico", "icns", "raw", "cr2",
        "nef", "arw", "dng", "svg", "pdf"
    ]

    /// Maximum thumbnail size
    private static let thumbnailSize = CGSize(width: 120, height: 120)

    /// Checks if a file URL points to an image file
    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// Generates a thumbnail for the given file URL
    /// - Parameter url: The file URL to generate a thumbnail for
    /// - Returns: PNG data for the thumbnail, or nil if generation failed
    static func generateThumbnail(for url: URL) -> Data? {
        // First try QuickLook thumbnailing (works for many file types)
        if let quickLookThumbnail = generateQuickLookThumbnail(for: url) {
            return quickLookThumbnail
        }

        // Fallback: try loading as NSImage directly for image files
        if isImageFile(url), let directThumbnail = generateDirectThumbnail(for: url) {
            return directThumbnail
        }

        return nil
    }

    /// Uses QuickLook to generate a thumbnail
    private static func generateQuickLookThumbnail(for url: URL) -> Data? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: 2.0, // Retina
            representationTypes: .thumbnail
        )

        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)

        QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, type, error in
            defer { semaphore.signal() }

            guard let thumbnail = thumbnail, error == nil else {
                return
            }

            // Convert to PNG data
            let image = thumbnail.nsImage
            result = pngData(from: image)
        }

        // Wait with timeout
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }

    /// Loads image directly and creates a thumbnail
    private static func generateDirectThumbnail(for url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        // Resize to thumbnail size
        let resized = resizeImage(image, to: thumbnailSize)
        return pngData(from: resized)
    }

    /// Resizes an image to fit within the given size while maintaining aspect ratio
    private static func resizeImage(_ image: NSImage, to maxSize: CGSize) -> NSImage {
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            return image
        }

        // Calculate scale to fit within maxSize
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = min(widthRatio, heightRatio, 1.0) // Don't upscale

        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }

    /// Converts an NSImage to PNG data
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}
