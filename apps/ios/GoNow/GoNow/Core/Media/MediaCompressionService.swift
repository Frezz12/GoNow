import AVFoundation
import Foundation
import ImageIO
import UIKit

enum MediaCompressionError: LocalizedError, Sendable {
    case unreadableImage
    case videoExportUnavailable
    case videoExportFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Не удалось подготовить изображение."
        case .videoExportUnavailable:
            "Это видео не удаётся сжать на устройстве."
        case .videoExportFailed:
            "Не удалось подготовить видео к отправке."
        }
    }
}

enum MediaOptimizationQuality: String, CaseIterable, Identifiable, Sendable {
    case dataSaver
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dataSaver: "Экономия"
        case .balanced: "Стандарт"
        }
    }

    var imageDimension: CGFloat { self == .dataSaver ? 1_280 : 1_600 }
    var imageQuality: CGFloat { self == .dataSaver ? 0.64 : 0.74 }
    var videoPreset: String {
        self == .dataSaver ? AVAssetExportPreset960x540 : AVAssetExportPreset1280x720
    }
}

struct OptimizedVideo: Sendable {
    let data: Data
    let fileName: String
    let contentType: String
    let duration: Double
}

struct MediaCompressionService: Sendable {
    func optimizeImage(
        _ source: Data,
        quality: MediaOptimizationQuality = .dataSaver
    ) async throws -> Data {
        try await optimizeImage(
            source,
            maxDimension: quality.imageDimension,
            compressionQuality: quality.imageQuality
        )
    }

    func optimizeImage(
        _ source: Data,
        maxDimension: CGFloat,
        compressionQuality: CGFloat
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard maxDimension > 0,
                  let imageSource = CGImageSourceCreateWithData(source as CFData, nil) else {
                throw MediaCompressionError.unreadableImage
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension.rounded(.up)),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                options as CFDictionary
            ) else {
                throw MediaCompressionError.unreadableImage
            }
            let targetSize = CGSize(width: decoded.width, height: decoded.height)
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = true
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let image = UIImage(cgImage: decoded, scale: 1, orientation: .up)
            let data = renderer.jpegData(withCompressionQuality: min(max(compressionQuality, 0), 1)) { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: targetSize))
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            guard !data.isEmpty else { throw MediaCompressionError.unreadableImage }
            return data
        }.value
    }

    func optimizeVideo(
        at sourceURL: URL,
        quality: MediaOptimizationQuality = .dataSaver
    ) async throws -> OptimizedVideo {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: quality.videoPreset) else {
            throw MediaCompressionError.videoExportUnavailable
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoNowOutgoingMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)

        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: outputURL, options: .mappedIfSafe)
        }.value
        try? FileManager.default.removeItem(at: outputURL)
        guard !data.isEmpty else { throw MediaCompressionError.videoExportFailed }
        let duration = try await asset.load(.duration).seconds
        return OptimizedVideo(
            data: data,
            fileName: "video-\(UUID().uuidString).mp4",
            contentType: "video/mp4",
            duration: duration.isFinite ? duration : 0
        )
    }
}
