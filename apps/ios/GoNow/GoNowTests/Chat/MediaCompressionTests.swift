import UIKit
import XCTest
@testable import GoNow

final class MediaCompressionTests: XCTestCase {
    func testImageOptimizationProducesBoundedJPEG() async throws {
        let sourceSize = CGSize(width: 2_400, height: 1_800)
        let source = UIGraphicsImageRenderer(size: sourceSize).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let sourceData = try XCTUnwrap(source.pngData())

        let optimized = try await MediaCompressionService().optimizeImage(
            sourceData,
            quality: .dataSaver
        )
        let image = try XCTUnwrap(UIImage(data: optimized))

        XCTAssertTrue(optimized.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1_280)
        XCTAssertFalse(optimized.isEmpty)
    }

    func testDataSaverUsesSmallerTargetsThanBalanced() {
        XCTAssertLessThan(
            MediaOptimizationQuality.dataSaver.imageDimension,
            MediaOptimizationQuality.balanced.imageDimension
        )
        XCTAssertLessThan(
            MediaOptimizationQuality.dataSaver.imageQuality,
            MediaOptimizationQuality.balanced.imageQuality
        )
    }
}
