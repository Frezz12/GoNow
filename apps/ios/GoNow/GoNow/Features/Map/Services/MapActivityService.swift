import Foundation

/// Authenticated transport for the activity map API.
struct MapActivityService: MapActivityRepository {
    let apiClient: APIClient

    func activities(in viewport: MapViewport, filters: MapFilterState) async throws -> MapActivityPage {
        let requestedBounds = viewport.bounds.expanded()
        var query = [
            URLQueryItem(name: "south", value: String(requestedBounds.south)),
            URLQueryItem(name: "west", value: String(requestedBounds.west)),
            URLQueryItem(name: "north", value: String(requestedBounds.north)),
            URLQueryItem(name: "east", value: String(requestedBounds.east)),
            URLQueryItem(name: "zoom", value: String(viewport.zoom)),
            URLQueryItem(name: "onlyAvailable", value: String(filters.onlyAvailable)),
            URLQueryItem(name: "limit", value: "1000")
        ]
        if !filters.categories.isEmpty {
            query.append(URLQueryItem(
                name: "categories",
                value: filters.categories.map(\.rawValue).sorted().joined(separator: ",")
            ))
        }
        if let hours = filters.startsWithinHours {
            query.append(URLQueryItem(name: "startsFrom", value: Self.iso8601.string(from: Date())))
            query.append(URLQueryItem(name: "startsTo", value: Self.iso8601.string(from: Date().addingTimeInterval(Double(hours) * 3_600))))
        }
        let envelope: MapActivityEnvelopeDTO = try await apiClient.get("activities/map", queryItems: query)
        return envelope.page
    }

    func createActivity(_ activity: CreateMapActivity) async throws -> MapActivity {
        let request = CreateMapActivityDTO(
            title: activity.title,
            category: activity.category,
            latitude: activity.coordinate.latitude,
            longitude: activity.coordinate.longitude,
            startsAt: activity.startsAt,
            participantLimit: activity.participantLimit
        )
        let envelope: APIEnvelope<GoNowActivity> = try await apiClient.post(
            "activities",
            body: request,
            authenticated: true
        )
        let created = envelope.data
        return MapActivity(
            id: created.id.uuidString,
            title: created.title,
            category: created.category,
            coordinate: created.location.coordinate,
            startsAt: created.startsAt,
            participantCount: created.participantCount,
            participantLimit: created.participantLimit,
            distanceMeters: 0,
            imageURL: nil,
            isJoined: true
        )
    }

    private static let iso8601 = ISO8601DateFormatter()
}

private struct MapActivityEnvelopeDTO: Decodable, Sendable {
    let data: MapActivityPageDTO
    let meta: MapActivityMetaDTO

    var page: MapActivityPage {
        MapActivityPage(activities: data.activities, nextCursor: meta.nextCursor, loadedBounds: data.viewport)
    }
}

private struct MapActivityPageDTO: Decodable, Sendable {
    let activities: [MapActivity]
    let viewport: MapBounds
}

private struct MapActivityMetaDTO: Decodable, Sendable {
    let count: Int
    let truncated: Bool
    let nextCursor: String?

}

private struct CreateMapActivityDTO: Encodable, Sendable {
    let title: String
    let category: ActivityCategory
    let latitude: Double
    let longitude: Double
    let startsAt: Date?
    let participantLimit: Int?
}
