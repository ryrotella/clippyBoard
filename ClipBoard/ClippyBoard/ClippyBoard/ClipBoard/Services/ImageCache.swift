import AppKit
import Foundation

/// Memory-efficient image cache using NSCache for clipboard item thumbnails
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, NSImage>
    private let maxCacheSizeBytes: Int = 50 * 1024 * 1024 // 50MB

    private init() {
        cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = maxCacheSizeBytes
        cache.countLimit = 200 // Maximum number of images

        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: NSApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Retrieves an image from cache or decodes it from data
    /// - Parameters:
    ///   - data: The image data to decode if not cached
    ///   - key: A unique key for the image (typically item UUID)
    /// - Returns: The cached or newly decoded NSImage, or nil if decoding fails
    func image(for data: Data, key: String) -> NSImage? {
        let cacheKey = key as NSString

        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        // Decode and cache
        guard let image = NSImage(data: data) else {
            return nil
        }

        // Estimate memory cost based on image dimensions
        let cost = estimateCost(for: image)
        cache.setObject(image, forKey: cacheKey, cost: cost)

        return image
    }

    /// Preloads an image into the cache
    func preload(data: Data, key: String) {
        _ = image(for: data, key: key)
    }

    /// Removes a specific image from the cache
    func remove(key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// Clears all cached images
    @objc func clearCache() {
        cache.removeAllObjects()
    }

    private func estimateCost(for image: NSImage) -> Int {
        // Estimate bytes: width * height * 4 (RGBA)
        let size = image.size
        return Int(size.width * size.height * 4)
    }
}

// Add memory warning notification name for macOS
extension NSApplication {
    static let didReceiveMemoryWarningNotification = Notification.Name("NSApplicationDidReceiveMemoryWarningNotification")
}
