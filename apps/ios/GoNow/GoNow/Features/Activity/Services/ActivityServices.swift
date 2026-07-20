import CoreLocation
import Foundation
import MapKit
import UIKit

actor ActivityDraftStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> ActivityDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(ActivityDraft.self, from: data)
    }

    func save(_ draft: ActivityDraft) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(draft).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GoNow/ActivityDraft/current.json")
    }
}

enum ActivityPhotoProcessingError: LocalizedError, Sendable {
    case unreadableImage

    var errorDescription: String? { L10n.string("activity.photos.error") }
}

struct ActivityPhotoCompressor: Sendable {
    func compress(_ source: Data, maxDimension: CGFloat = 1_600, quality: CGFloat = 0.72) async throws -> Data {
        do {
            return try await MediaCompressionService().optimizeImage(
                source,
                maxDimension: maxDimension,
                compressionQuality: quality
            )
        } catch {
            throw ActivityPhotoProcessingError.unreadableImage
        }
    }
}

@MainActor
final class ActivityLocationSearchService: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var onSuggestions: ((String, [ActivityLocationSuggestion]) -> Void)?
    var onFailure: ((String, Error) -> Void)?

    private let completer: MKLocalSearchCompleter
    private var completionsByID: [UUID: MKLocalSearchCompletion] = [:]
    private var currentQuery = ""

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String, region: MKCoordinateRegion?) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanQuery.count >= 2 else {
            clear()
            return
        }
        currentQuery = cleanQuery
        completionsByID = [:]
        if let region { completer.region = region }
        completer.queryFragment = cleanQuery
    }

    func clear() {
        currentQuery = ""
        completionsByID = [:]
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !currentQuery.isEmpty else { return }
        var seen = Set<String>()
        var nextCompletions: [UUID: MKLocalSearchCompletion] = [:]
        let suggestions = completer.results.compactMap { completion -> ActivityLocationSuggestion? in
            let key = "\(completion.title)|\(completion.subtitle)".lowercased()
            guard seen.insert(key).inserted else { return nil }
            let id = UUID()
            nextCompletions[id] = completion
            return ActivityLocationSuggestion(
                id: id,
                title: completion.title,
                subtitle: completion.subtitle
            )
        }.prefix(8).map { $0 }
        completionsByID = nextCompletions
        onSuggestions?(currentQuery, suggestions)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard !currentQuery.isEmpty else { return }
        onFailure?(currentQuery, error)
    }

    func resolve(_ suggestion: ActivityLocationSuggestion) async throws -> ActivityLocationSuggestion {
        let request: MKLocalSearch.Request
        if let completion = completionsByID[suggestion.id] {
            request = MKLocalSearch.Request(completion: completion)
        } else {
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = suggestion.displayAddress
            request.resultTypes = [.address, .pointOfInterest]
        }
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw ActivityLocationSearchError.notFound
        }
        return ActivityLocationSuggestion(
            id: suggestion.id,
            title: item.name ?? suggestion.title,
            subtitle: item.address?.fullAddress ?? suggestion.subtitle,
            coordinate: MapCoordinate(
                latitude: item.location.coordinate.latitude,
                longitude: item.location.coordinate.longitude
            )
        )
    }

    func address(for coordinate: MapCoordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return item.address?.fullAddress ?? item.name
    }
}

private enum ActivityLocationSearchError: LocalizedError {
    case notFound

    var errorDescription: String? { L10n.string("activity.location.search.error") }
}
