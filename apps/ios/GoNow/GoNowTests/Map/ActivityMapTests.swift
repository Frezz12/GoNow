import CoreLocation
import XCTest
@testable import GoNow

final class ActivityMapTests: XCTestCase {
    func testBoundsContainmentAndExpansion() {
        let bounds = MapBounds(south: 55.0, west: 37.0, north: 56.0, east: 38.0)
        XCTAssertTrue(bounds.contains(MapCoordinate(latitude: 55.5, longitude: 37.5)))
        XCTAssertFalse(bounds.contains(MapCoordinate(latitude: 54.9, longitude: 37.5)))

        let expanded = bounds.expanded(by: 0.2)
        XCTAssertEqual(expanded.south, 54.8, accuracy: 0.0001)
        XCTAssertEqual(expanded.east, 38.2, accuracy: 0.0001)
        XCTAssertTrue(expanded.contains(bounds))
    }

    func testBoundsCrossingAntimeridian() {
        let bounds = MapBounds(south: -20, west: 170, north: 20, east: -170)
        XCTAssertTrue(bounds.crossesAntimeridian)
        XCTAssertTrue(bounds.contains(MapCoordinate(latitude: 0, longitude: 179)))
        XCTAssertTrue(bounds.contains(MapCoordinate(latitude: 0, longitude: -179)))
        XCTAssertFalse(bounds.contains(MapCoordinate(latitude: 0, longitude: 0)))
        XCTAssertTrue(bounds.contains(MapBounds(south: -10, west: 175, north: 10, east: -175)))
        XCTAssertFalse(bounds.contains(MapBounds(south: -10, west: -175, north: 10, east: 175)))
    }

    func testNarrowBoundsDoNotContainAnAntimeridianWrappingViewport() {
        let bounds = MapBounds(south: -20, west: -10, north: 20, east: 10)
        let wrapping = MapBounds(south: -10, west: 5, north: 10, east: -175)
        XCTAssertFalse(bounds.contains(wrapping))
    }

    func testGlobalBoundsRemainGlobalAfterExpansion() {
        let global = MapBounds(south: -85, west: -180, north: 85, east: 180)
        let expanded = global.expanded(by: 0.2)
        XCTAssertEqual(expanded, global)
        XCTAssertTrue(expanded.contains(MapCoordinate(latitude: 84.9, longitude: 179.9)))
        XCTAssertTrue(expanded.contains(MapCoordinate(latitude: -84.9, longitude: -179.9)))
    }

    func testTinyAndPolarBoundsExpandSafely() {
        let tiny = MapBounds(south: 89.8, west: 12, north: 89.9, east: 12.1)
        let expanded = tiny.expanded(by: 0.2)
        XCTAssertEqual(expanded.north, 85)
        XCTAssertTrue(expanded.longitudeSpan > tiny.longitudeSpan)
    }

    func testMockRepositoryAppliesCategoryFilter() async throws {
        let repository = MockMapActivityRepository(delayNanoseconds: 0)
        let viewport = MapViewport(
            bounds: MapBounds(south: 55, west: 37, north: 56, east: 38),
            center: .moscow,
            zoom: 11
        )
        var filters = MapFilterState()
        filters.categories = [.sport]

        let page = try await repository.activities(in: viewport, filters: filters)
        XCTAssertFalse(page.activities.isEmpty)
        XCTAssertTrue(page.activities.allSatisfy { $0.category == .sport })
        XCTAssertTrue(page.loadedBounds.contains(viewport.bounds))
    }

    func testRenderPropertiesContainOnlyLightweightMapData() {
        let activity = MapActivity(
            id: "activity-1",
            title: "Run",
            category: .sport,
            coordinate: .moscow,
            startsAt: Date(timeIntervalSince1970: 1_700_000_000),
            participantCount: 4,
            participantLimit: 10,
            distanceMeters: 500,
            imageURL: URL(string: "https://example.com/image.jpg"),
            isJoined: false
        )
        let properties = activity.renderProperties(isSelected: true)
        XCTAssertEqual(properties.activityID, "activity-1")
        XCTAssertEqual(properties.category, "sport")
        XCTAssertTrue(properties.isSelected)
        XCTAssertEqual(properties.markerImage, "gonow-map-pin-sport-selected")
    }

    func testAllCategoriesHaveStableMarkerSymbols() {
        XCTAssertEqual(ActivityCategory.allCases.count, 11)
        XCTAssertTrue(ActivityCategory.allCases.allSatisfy {
            !$0.rawValue.isEmpty
                && !$0.symbol.isEmpty
                && $0.markerImageName.hasPrefix("gonow-map-pin-")
        })
        XCTAssertEqual(Set(ActivityCategory.allCases.map(\.markerImageName)).count, ActivityCategory.allCases.count)
    }

    func testCacheReturnsPageForContainedViewportAndMatchingFilters() async {
        let cache = MapActivityPageCache(capacity: 2, ttl: 60)
        let bounds = MapBounds(south: 50, west: 30, north: 60, east: 40)
        let page = MapActivityPage(activities: [], nextCursor: nil, loadedBounds: bounds)
        await cache.insert(page, filters: MapFilterState(), now: Date(timeIntervalSince1970: 100))

        let contained = MapBounds(south: 52, west: 32, north: 58, east: 38)
        let result = await cache.value(containing: contained, filters: MapFilterState(), now: Date(timeIntervalSince1970: 120))
        XCTAssertEqual(result, page)
    }

    func testCameraStoreRoundTrip() {
        let suite = "ActivityMapTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MapCameraStore(defaults: defaults)
        let camera = PersistedMapCamera(center: .moscow, zoom: 12, bearing: 15, pitch: 30)
        store.save(camera)
        XCTAssertEqual(store.load(), camera)
    }

    @MainActor
    func testActivityListCalculatesDistanceAndSortsNearestFirst() {
        let origin = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        let farther = mapActivity(id: "farther", latitude: 55.8058, longitude: 37.6173)
        let nearer = mapActivity(id: "nearer", latitude: 55.7658, longitude: 37.6173)

        let items = ActivitiesListViewModel.makeItems(
            activities: [farther, nearer],
            userCoordinate: origin
        )

        XCTAssertEqual(items.map(\.id), ["nearer", "farther"])
        XCTAssertNotNil(items[0].distanceMeters)
        XCTAssertLessThan(items[0].distanceMeters ?? .greatestFiniteMagnitude, items[1].distanceMeters ?? 0)
    }

    private func mapActivity(id: String, latitude: Double, longitude: Double) -> MapActivity {
        MapActivity(
            id: id,
            title: id,
            category: .walking,
            coordinate: MapCoordinate(latitude: latitude, longitude: longitude),
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            participantCount: 1,
            participantLimit: nil,
            distanceMeters: nil,
            imageURL: nil,
            isJoined: false
        )
    }
}
