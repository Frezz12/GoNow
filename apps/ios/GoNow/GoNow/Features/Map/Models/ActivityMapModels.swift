import Foundation

struct MapCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    static let moscow = MapCoordinate(latitude: 55.7558, longitude: 37.6173)
    static let europe = MapCoordinate(latitude: 50.0, longitude: 10.0)

    var isValid: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

struct MapBounds: Codable, Equatable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    var crossesAntimeridian: Bool { west > east }

    var longitudeSpan: Double {
        if west == -180, east == 180 { return 360 }
        return crossesAntimeridian ? (180 - west) + (east + 180) : east - west
    }

    func contains(_ coordinate: MapCoordinate) -> Bool {
        guard coordinate.latitude >= south, coordinate.latitude <= north else { return false }
        return crossesAntimeridian
            ? coordinate.longitude >= west || coordinate.longitude <= east
            : coordinate.longitude >= west && coordinate.longitude <= east
    }

    func contains(_ other: MapBounds) -> Bool {
        guard other.south >= south, other.north <= north else { return false }
        let epsilon = 0.000_001
        guard longitudeSpan < 360 - epsilon else { return true }
        guard other.longitudeSpan < 360 - epsilon else { return false }
        let startOffset = Self.eastwardDistance(from: west, to: other.west)
        return startOffset + other.longitudeSpan <= longitudeSpan + epsilon
    }

    func expanded(by factor: Double = 0.2) -> MapBounds {
        let safeFactor = max(0, factor)
        let latitudePadding = (north - south) * safeFactor
        let longitudePadding = longitudeSpan * safeFactor
        let expandedLongitudeSpan = longitudeSpan + (longitudePadding * 2)
        return MapBounds(
            south: max(-85, min(85, south - latitudePadding)),
            west: expandedLongitudeSpan >= 360 ? -180 : Self.normalizedLongitude(west - longitudePadding),
            north: min(85, max(-85, north + latitudePadding)),
            east: expandedLongitudeSpan >= 360 ? 180 : Self.normalizedLongitude(east + longitudePadding)
        )
    }

    private static func normalizedLongitude(_ value: Double) -> Double {
        var result = value
        while result > 180 { result -= 360 }
        while result < -180 { result += 360 }
        return result
    }

    private static func eastwardDistance(from start: Double, to end: Double) -> Double {
        var distance = (end - start).truncatingRemainder(dividingBy: 360)
        if distance < 0 { distance += 360 }
        return distance
    }
}

struct MapViewport: Codable, Equatable, Sendable {
    let bounds: MapBounds
    let center: MapCoordinate
    let zoom: Double
}

enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case sport
    case walking
    case travel
    case music
    case games
    case help
    case education
    case animals
    case other

    var id: String { rawValue }
    var titleKey: String { "map.category.\(rawValue)" }
    var symbol: String {
        switch self {
        case .sport: "figure.run"
        case .walking: "figure.walk"
        case .travel: "airplane"
        case .music: "music.note"
        case .games: "gamecontroller.fill"
        case .help: "hand.raised.fill"
        case .education: "book.fill"
        case .animals: "pawprint.fill"
        case .other: "sparkles"
        }
    }
}

struct MapFilterState: Codable, Equatable, Sendable {
    var categories: Set<ActivityCategory> = []
    var startsWithinHours: Int?
    var onlyAvailable = false

    var isEmpty: Bool {
        categories.isEmpty && startsWithinHours == nil && !onlyAvailable
    }

    var activeCount: Int {
        categories.count + (startsWithinHours == nil ? 0 : 1) + (onlyAvailable ? 1 : 0)
    }
}

struct MapActivity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: ActivityCategory
    let coordinate: MapCoordinate
    let startsAt: Date
    let participantCount: Int
    let participantLimit: Int?
    let distanceMeters: Double?
    let imageURL: URL?
    let isJoined: Bool

    var isFull: Bool {
        guard let participantLimit else { return false }
        return participantCount >= participantLimit
    }

    func renderProperties(isSelected: Bool = false) -> MapActivityRenderProperties {
        MapActivityRenderProperties(
            activityID: id,
            category: category.rawValue,
            title: title,
            participantCount: participantCount,
            participantLimit: participantLimit,
            isFull: isFull,
            isSelected: isSelected,
            markerImage: isSelected ? "gonow-map-point-selected" : "gonow-map-point"
        )
    }
}

struct MapActivityRenderProperties: Equatable, Sendable {
    let activityID: String
    let category: String
    let title: String
    let participantCount: Int
    let participantLimit: Int?
    let isFull: Bool
    let isSelected: Bool
    let markerImage: String
}

struct CreateMapActivity: Codable, Equatable, Sendable {
    let title: String
    let category: ActivityCategory
    let coordinate: MapCoordinate
    let startsAt: Date?
    let participantLimit: Int?
}

struct MapActivityPage: Codable, Equatable, Sendable {
    let activities: [MapActivity]
    let nextCursor: String?
    let loadedBounds: MapBounds
}

enum MapContentState: Equatable, Sendable {
    case initial
    case loading
    case loaded
    case empty
    case failed(message: String, keepsExistingData: Bool)
}

struct PersistedMapCamera: Codable, Equatable, Sendable {
    let center: MapCoordinate
    let zoom: Double
    let bearing: Double
    let pitch: Double
}
