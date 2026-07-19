import Combine
import Foundation
import OSLog

struct MapStyleDocument: Equatable {
    let id = UUID()
    let json: String
}

@MainActor
final class MapStyleLoader: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(MapStyleDocument)
        case failed
    }

    @Published private(set) var state: State = .idle

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "GoNow",
        category: "MapStyle"
    )

    private let session: URLSession
    private var loadTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        loadTask?.cancel()
    }

    var loadedDocumentID: UUID? {
        guard case .loaded(let document) = state else { return nil }
        return document.id
    }

    func load() {
        guard case .idle = state else { return }
        startLoading()
    }

    func reload() {
        startLoading()
    }

    private func startLoading() {
        loadTask?.cancel()
        state = .loading

        var components = URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("map/style"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "contract", value: "5"),
            URLQueryItem(name: "request", value: UUID().uuidString),
        ]

        guard let url = components?.url else {
            state = .failed
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        loadTask = Task { [weak self, session] in
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      Self.isValidStyle(data),
                      let json = String(data: data, encoding: .utf8) else {
                    throw MapStyleLoaderError.invalidResponse
                }
                self?.state = .loaded(MapStyleDocument(json: json))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
                Self.logger.error("Map style request failed: \(error.localizedDescription, privacy: .public)")
                self?.state = .failed
            }
        }
    }

    private static func isValidStyle(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? NSNumber,
              version.intValue == 8,
              object["sources"] is [String: Any],
              object["layers"] is [[String: Any]] else {
            return false
        }
        return true
    }
}

private enum MapStyleLoaderError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The map style response is invalid."
    }
}
