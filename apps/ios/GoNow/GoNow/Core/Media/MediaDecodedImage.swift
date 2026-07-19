import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// A small decoded-image cache separate from the raw media cache. Decoding is
/// performed off the main actor and thumbnails are created at their display size,
/// avoiding repeated full-resolution `UIImage(data:)` work during SwiftUI updates.
actor MediaImageDecoder {
    static let shared = MediaImageDecoder()

    private let cache = NSCache<NSString, UIImage>()

    init(memoryLimit: Int = 48 * 1024 * 1024) {
        cache.totalCostLimit = memoryLimit
        cache.countLimit = 96
    }

    func image(from data: Data, cacheKey: String?, maxPixelSize: Int) async -> UIImage? {
        guard !data.isEmpty else { return nil }
        let digest = cacheKey ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "\(digest)#\(maxPixelSize)" as NSString
        if let image = cache.object(forKey: key) { return image }

        let image = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as UIImage? }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: decoded, scale: 1, orientation: .up)
        }.value

        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }
}

private struct MediaImageRequestID: Hashable {
    let cacheKey: String?
    let byteCount: Int
    let prefix: UInt64
    let suffix: UInt64
    let maxPixelSize: Int

    init(data: Data, cacheKey: String?, maxPixelSize: Int) {
        self.cacheKey = cacheKey
        byteCount = data.count
        prefix = Self.sample(data.prefix(8))
        suffix = Self.sample(data.suffix(8))
        self.maxPixelSize = maxPixelSize
    }

    private static func sample<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }
}

struct MediaDecodedImage<Placeholder: View>: View {
    let data: Data
    let cacheKey: String?
    let maxPixelSize: Int
    let contentMode: ContentMode
    private let placeholder: Placeholder
    @State private var image: UIImage?

    init(
        data: Data,
        cacheKey: String? = nil,
        maxPixelSize: Int,
        contentMode: ContentMode,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.data = data
        self.cacheKey = cacheKey
        self.maxPixelSize = max(1, maxPixelSize)
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: MediaImageRequestID(data: data, cacheKey: cacheKey, maxPixelSize: maxPixelSize)) {
            image = nil
            image = await MediaImageDecoder.shared.image(
                from: data,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            )
        }
    }
}
