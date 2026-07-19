import Foundation
import XCTest
@testable import GoNow

final class MediaDataCacheTests: XCTestCase {
    func testConcurrentRequestsShareOneLoadAndPersistToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoNowMediaDataCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data("cached-image".utf8)
        let counter = LoaderCounter()
        let cache = MediaDataCache(directory: directory, memoryLimit: 1024, diskLimit: 4096)

        async let first = cache.data(for: "photo-1") {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return payload
        }
        async let second = cache.data(for: "photo-1") {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return payload
        }

        let loaded = try await [first, second]
        XCTAssertEqual(loaded, [payload, payload])
        let loadCount = await counter.value
        XCTAssertEqual(loadCount, 1)

        let diskCache = MediaDataCache(directory: directory, memoryLimit: 1024, diskLimit: 4096)
        let diskPayload = try await diskCache.data(for: "photo-1") {
            throw UnexpectedNetworkLoad()
        }
        XCTAssertEqual(diskPayload, payload)
    }
}

private actor LoaderCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct UnexpectedNetworkLoad: Error { }
