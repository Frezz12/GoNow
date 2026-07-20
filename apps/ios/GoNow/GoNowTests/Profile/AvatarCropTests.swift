import XCTest
import UIKit
@testable import GoNow

final class AvatarCropTests: XCTestCase {
    func testCenteredLandscapeCropUsesMiddleSquare() {
        let rect = AvatarCropGeometry.sourceRect(
            imageSize: CGSize(width: 200, height: 100),
            cropSide: 100,
            zoom: 1,
            offset: .zero
        )

        XCTAssertEqual(rect.origin.x, 50, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
    }

    func testOffsetCannotExposeAreaOutsideImage() {
        let offset = AvatarCropGeometry.clampedOffset(
            CGSize(width: 500, height: 500),
            imageSize: CGSize(width: 200, height: 100),
            cropSide: 100,
            zoom: 1
        )

        XCTAssertEqual(offset.width, 50, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }

    func testZoomedCropProducesSquareAvatarData() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let data = try await AvatarCropProcessor.croppedJPEG(
            from: source,
            cropSide: 100,
            zoom: 2,
            offset: .zero
        )
        let result = try XCTUnwrap(UIImage(data: data)?.cgImage)

        XCTAssertEqual(result.width, 1_024)
        XCTAssertEqual(result.height, 1_024)
    }
}
