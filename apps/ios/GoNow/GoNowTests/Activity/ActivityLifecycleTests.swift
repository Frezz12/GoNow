import Foundation
import XCTest
@testable import GoNow

final class ActivityLifecycleTests: XCTestCase {
    func testNewDraftAppearsOnMapAtStartByDefault() {
        var draft = ActivityDraft()
        draft.startsAt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(draft.showTiming, .atStart)
        XCTAssertEqual(draft.showAfter, draft.startsAt)
    }

    func testDraftCalculatesVisibilityWindowFromSchedule() {
        var draft = ActivityDraft()
        draft.startsAt = Date(timeIntervalSince1970: 1_800_000_000)
        draft.durationPreset = .twoHours
        draft.showTiming = .oneDay
        draft.hideTiming = .oneHourAfterEnd

        XCTAssertEqual(draft.durationMinutes, 120)
        XCTAssertEqual(draft.showAfter, draft.startsAt.addingTimeInterval(-86_400))
        XCTAssertEqual(draft.hideAfter, draft.startsAt.addingTimeInterval(10_800))
    }

    func testLocationSuggestionBuildsReadableNormalizedAddress() {
        let suggestion = ActivityLocationSuggestion(
            title: "Царицыно",
            subtitle: "Москва, Россия"
        )

        XCTAssertEqual(suggestion.displayAddress, "Царицыно, Москва, Россия")
        XCTAssertNil(suggestion.coordinate)
    }

    func testLocationSuggestionDoesNotDuplicateTitleAlreadyInAddress() {
        let suggestion = ActivityLocationSuggestion(
            title: "Царицыно",
            subtitle: "метро Царицыно, Москва"
        )

        XCTAssertEqual(suggestion.displayAddress, "метро Царицыно, Москва")
    }

    func testDraftStoreRoundTripAndClear() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("draft.json")
        let store = ActivityDraftStore(fileURL: fileURL)
        var draft = completeDraft()
        draft.title = "Saved activity"

        try await store.save(draft)
        let loaded = await store.load()
        XCTAssertEqual(loaded?.id, draft.id)
        XCTAssertEqual(loaded?.title, draft.title)
        XCTAssertEqual(loaded?.location, draft.location)
        XCTAssertEqual(loaded?.startsAt, draft.startsAt)

        try await store.clear()
        let cleared = await store.load()
        XCTAssertNil(cleared)
    }

    func testMockRepositoryCoversCreatePhotoApplicationsAndRepeat() async throws {
        let repository = MockActivityRepository()
        let draft = completeDraft(photoData: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let created = try await repository.create(from: draft, status: .published)
        XCTAssertEqual(created.status, .published)
        XCTAssertEqual(created.photos.count, 1)
        XCTAssertTrue(created.photos[0].isCover)
        let storedPhoto = try await repository.photoData(for: created.photos[0])
        XCTAssertEqual(storedPhoto, draft.photos[0].data)

        let application = try await repository.apply(
            activityID: created.id,
            message: "I would like to join",
            answers: []
        )
        XCTAssertEqual(application.status, .pending)
        let accepted = try await repository.updateApplication(
            activityID: created.id,
            applicationID: application.id,
            status: .accepted
        )
        XCTAssertEqual(accepted.status, .accepted)

        let completed = try await repository.update(
            id: created.id,
            changes: ActivityUpdate(status: .completed)
        )
        XCTAssertEqual(completed.status, .completed)

        let repeated = try await repository.duplicate(activityID: created.id)
        XCTAssertEqual(repeated.status, .draft)
        XCTAssertEqual(repeated.title, created.title)
    }

    private func completeDraft(photoData: Data? = nil) -> ActivityDraft {
        var draft = ActivityDraft()
        draft.title = "Morning walk"
        draft.description = "A relaxed walk through the city park."
        draft.category = .walking
        draft.location = ActivityLocation(
            coordinate: MapCoordinate(latitude: 55.751244, longitude: 37.618423),
            address: "City park",
            venueName: "Main entrance",
            visibility: .acceptedParticipants,
            isExact: true
        )
        draft.startsAt = Date(timeIntervalSince1970: 1_800_000_000)
        draft.joinPolicy = .request
        if let photoData {
            draft.photos = [ActivityDraftPhoto(data: photoData, isCover: true)]
        }
        return draft
    }
}
