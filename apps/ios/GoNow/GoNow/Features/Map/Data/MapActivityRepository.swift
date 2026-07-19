import Foundation

protocol MapActivityRepository: Sendable {
    func activities(in viewport: MapViewport, filters: MapFilterState) async throws -> MapActivityPage
    func createActivity(_ activity: CreateMapActivity) async throws -> MapActivity
}

enum MapActivityRepositoryError: Error, Sendable {
    case serviceUnavailable
}

actor MapActivityPageCache {
    private struct Entry {
        let page: MapActivityPage
        let filters: MapFilterState
        let expiresAt: Date
        var lastAccessedAt: Date
    }

    private var entries: [Entry] = []
    private let capacity: Int
    private let ttl: TimeInterval

    init(capacity: Int = 8, ttl: TimeInterval = 60) {
        self.capacity = max(1, capacity)
        self.ttl = ttl
    }

    func value(containing bounds: MapBounds, filters: MapFilterState, now: Date = Date()) -> MapActivityPage? {
        entries.removeAll { $0.expiresAt <= now }
        guard let index = entries.firstIndex(where: { $0.filters == filters && $0.page.loadedBounds.contains(bounds) }) else {
            return nil
        }
        entries[index].lastAccessedAt = now
        return entries[index].page
    }

    func insert(_ page: MapActivityPage, filters: MapFilterState, now: Date = Date()) {
        entries.append(Entry(page: page, filters: filters, expiresAt: now.addingTimeInterval(ttl), lastAccessedAt: now))
        if entries.count > capacity {
            entries.sort { $0.lastAccessedAt > $1.lastAccessedAt }
            entries.removeLast(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

struct CachedMapActivityRepository: MapActivityRepository {
    let upstream: any MapActivityRepository
    let cache: MapActivityPageCache

    func activities(in viewport: MapViewport, filters: MapFilterState) async throws -> MapActivityPage {
        if let cached = await cache.value(containing: viewport.bounds, filters: filters) { return cached }
        let page = try await upstream.activities(in: viewport, filters: filters)
        await cache.insert(page, filters: filters)
        return page
    }

    func createActivity(_ activity: CreateMapActivity) async throws -> MapActivity {
        let created = try await upstream.createActivity(activity)
        await cache.clear()
        return created
    }
}

actor MockMapActivityRepository: MapActivityRepository {
    let delayNanoseconds: UInt64
    private var createdActivities: [MapActivity]

    init(delayNanoseconds: UInt64 = 250_000_000, createdActivities: [MapActivity] = []) {
        self.delayNanoseconds = delayNanoseconds
        self.createdActivities = createdActivities
    }

    func activities(in viewport: MapViewport, filters: MapFilterState) async throws -> MapActivityPage {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        let expanded = viewport.bounds.expanded()
        let now = Date()
        let categories = ActivityCategory.allCases
        let demoActivities = (0..<96).compactMap { index -> MapActivity? in
            let seed = Double(index + 1)
            let latitude = viewport.center.latitude + sin(seed * 1.73) * 0.18
            let longitude = viewport.center.longitude + cos(seed * 1.21) * 0.28
            let category = categories[index % categories.count]
            let activity = MapActivity(
                id: "demo-\(index)",
                title: L10n.format("map.demo.activity.title", index + 1),
                category: category,
                coordinate: MapCoordinate(latitude: latitude, longitude: longitude),
                startsAt: now.addingTimeInterval(Double((index % 48) + 1) * 1_800),
                participantCount: (index * 3) % 22 + 1,
                participantLimit: 20,
                distanceMeters: nil,
                imageURL: nil,
                isJoined: index.isMultiple(of: 11)
            )
            guard expanded.contains(activity.coordinate) else { return nil }
            guard filters.categories.isEmpty || filters.categories.contains(category) else { return nil }
            if let hours = filters.startsWithinHours,
               activity.startsAt > now.addingTimeInterval(Double(hours) * 3_600) { return nil }
            if filters.onlyAvailable && activity.isFull { return nil }
            return activity
        }
        let created = createdActivities.filter { activity in
            expanded.contains(activity.coordinate)
                && (filters.categories.isEmpty || filters.categories.contains(activity.category))
        }
        return MapActivityPage(activities: created + demoActivities, nextCursor: nil, loadedBounds: expanded)
    }

    func createActivity(_ activity: CreateMapActivity) async throws -> MapActivity {
        let created = MapActivity(
            id: UUID().uuidString,
            title: activity.title,
            category: activity.category,
            coordinate: activity.coordinate,
            startsAt: activity.startsAt ?? Date(),
            participantCount: 1,
            participantLimit: activity.participantLimit,
            distanceMeters: 0,
            imageURL: nil,
            isJoined: true
        )
        createdActivities.insert(created, at: 0)
        return created
    }
}
