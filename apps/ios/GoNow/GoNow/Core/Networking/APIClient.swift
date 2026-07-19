import Foundation

enum APIError: LocalizedError, Sendable {
    case server(APIErrorBody)
    case unauthorized
    case invalidResponse
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .server(let error): return LocalizedBackendError.message(for: error.code)
        case .unauthorized: return L10n.string("error.auth.unauthorized")
        case .invalidResponse: return L10n.string("error.network.invalid_response")
        case .transport: return L10n.string("error.network.transport")
        case .decoding: return L10n.string("error.network.decoding")
        }
    }

    var fieldErrors: [String: String] { if case .server(let error) = self { return error.fields ?? [:] }; return [:] }

    var invalidatesSession: Bool {
        switch self {
        case .unauthorized:
            true
        case .server(let error):
            ["INVALID_REFRESH_TOKEN", "SESSION_REVOKED", "TOKEN_EXPIRED", "UNAUTHORIZED", "USER_DISABLED"]
                .contains(error.code)
        case .invalidResponse, .transport, .decoding:
            false
        }
    }
}

actor APIClient {
    private struct CachedResponse {
        let data: Data
        let expiresAt: ContinuousClock.Instant
    }

    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private let mediaCache: MediaDataCache
    private var refreshTask: Task<AuthData, Error>?
    private var webSockets: [String: URLSessionWebSocketTask] = [:]
    private var responseCache: [String: CachedResponse] = [:]
    private var responseTasks: [String: Task<Data, Error>] = [:]
    private var cacheGeneration: UInt = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        tokenStore: TokenStore,
        session: URLSession? = nil,
        mediaCache: MediaDataCache = .shared
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session ?? Self.optimizedSession()
        self.mediaCache = mediaCache
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private nonisolated static func optimizedSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "GoNowHTTPResponses"
        )
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    func post<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ path: String, body: Input, authenticated: Bool = false, retryAfterRefresh: Bool = true) async throws -> Output {
        let data = try encoder.encode(body)
        return try await request(path, method: "POST", body: data, authenticated: authenticated, retryAfterRefresh: retryAfterRefresh)
    }

    func postNoContent<Input: Encodable & Sendable>(_ path: String, body: Input) async throws {
        invalidateResponseCache()
        let data = try encoder.encode(body)
        _ = try await validatedRequest(
            path,
            method: "POST",
            body: data,
            contentType: "application/json",
            authenticated: true,
            retryAfterRefresh: true
        )
    }

    func patch<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ path: String, body: Input) async throws -> Output {
        let data = try encoder.encode(body)
        return try await request(path, method: "PATCH", body: data, authenticated: true, retryAfterRefresh: true)
    }

    func get<Output: Decodable & Sendable>(_ path: String) async throws -> Output {
        try await request(path, method: "GET", body: nil, authenticated: true, retryAfterRefresh: true)
    }

    func get<Output: Decodable & Sendable>(_ path: String, queryItems: [URLQueryItem], authenticated: Bool = true) async throws -> Output {
        try await request(path, method: "GET", body: nil, authenticated: authenticated, retryAfterRefresh: true, queryItems: queryItems)
    }

    /// Bypasses the short-lived response cache for realtime and user-initiated refreshes.
    /// Media downloads keep using their dedicated memory/disk cache through `getData`.
    func getFresh<Output: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Output {
        let data = try await validatedRequest(
            path,
            method: "GET",
            body: nil,
            contentType: nil,
            authenticated: authenticated,
            retryAfterRefresh: true,
            queryItems: queryItems
        )
        do { return try decoder.decode(Output.self, from: data) }
        catch { throw APIError.decoding }
    }

    func uploadImage<Output: Decodable & Sendable>(
        _ path: String,
        imageData: Data,
        queryItems: [URLQueryItem] = []
    ) async throws -> Output {
        let boundary = "GoNowBoundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return try await request(
            path,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            authenticated: true,
            retryAfterRefresh: true,
            queryItems: queryItems
        )
    }

    func uploadFile<Output: Decodable & Sendable>(
        _ path: String,
        data: Data,
        fileName: String,
        contentType: String,
        queryItems: [URLQueryItem] = [],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Output {
        let boundary = "GoNowBoundary-\(UUID().uuidString)"
        let safeName = fileName.replacingOccurrences(of: "\"", with: "")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        invalidateResponseCache()
        let responseData = try await validatedUpload(
            path,
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            authenticated: true,
            retryAfterRefresh: true,
            queryItems: queryItems,
            progress: progress
        )
        do { return try decoder.decode(Output.self, from: responseData) }
        catch { throw APIError.decoding }
    }

    func webSocketEvents<Output: Decodable & Sendable>(
        _ path: String,
        as type: Output.Type
    ) throws -> AsyncThrowingStream<Output, Error> {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        if let token = try tokenStore.read()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webSockets[path]?.cancel(with: .goingAway, reason: nil)
        let socket = session.webSocketTask(with: request)
        webSockets[path] = socket
        socket.resume()
        return AsyncThrowingStream { continuation in
            let receiver = Task {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .data(let value): data = value
                        case .string(let value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        continuation.yield(try decoder.decode(Output.self, from: data))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                receiver.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func sendWebSocketCommand<Input: Encodable & Sendable>(_ path: String, command: Input) async throws {
        guard let socket = webSockets[path] else { return }
        try await socket.send(.data(try encoder.encode(command)))
    }

    func closeWebSocket(_ path: String) {
        webSockets.removeValue(forKey: path)?.cancel(with: .goingAway, reason: nil)
    }

    func getData(_ path: String) async throws -> Data {
        let key = baseURL.appendingPathComponent(path).absoluteString
        return try await mediaCache.data(for: key) { [self] in
            try await validatedRequest(
                path,
                method: "GET",
                body: nil,
                contentType: nil,
                authenticated: true,
                retryAfterRefresh: true
            )
        }
    }

    func cacheData(_ data: Data, for path: String) async {
        let key = baseURL.appendingPathComponent(path).absoluteString
        await mediaCache.store(data, for: key)
    }

    func removeCachedData(for path: String) async {
        let key = baseURL.appendingPathComponent(path).absoluteString
        await mediaCache.removeValue(for: key)
    }

    func clearMediaCache() async {
        await mediaCache.removeAll()
    }

    /// Removes all user-scoped state held by the client. This must be called when
    /// authentication changes so cached responses and sockets cannot cross sessions.
    func clearSessionCaches() async {
        invalidateResponseCache()
        webSockets.values.forEach { $0.cancel(with: .goingAway, reason: nil) }
        webSockets.removeAll(keepingCapacity: false)
        refreshTask?.cancel()
        refreshTask = nil
        await mediaCache.removeAll()
    }

    func delete(_ path: String) async throws {
        invalidateResponseCache()
        _ = try await validatedRequest(path, method: "DELETE", body: nil, contentType: nil, authenticated: true, retryAfterRefresh: true)
    }

    func deleteDecodable<Output: Decodable & Sendable>(_ path: String) async throws -> Output {
        invalidateResponseCache()
        let data = try await validatedRequest(
            path,
            method: "DELETE",
            body: nil,
            contentType: nil,
            authenticated: true,
            retryAfterRefresh: true
        )
        do { return try decoder.decode(Output.self, from: data) }
        catch { throw APIError.decoding }
    }

    func refresh() async throws -> AuthData {
        if let task = refreshTask { return try await task.value }
        let task = Task<AuthData, Error> { [tokenStore] in
            guard let tokens = try tokenStore.read() else { throw APIError.unauthorized }
            let response: APIEnvelope<AuthData> = try await self.request("auth/refresh", method: "POST", body: try self.encoder.encode(RefreshPayload(refreshToken: tokens.refreshToken)), authenticated: false, retryAfterRefresh: false)
            try tokenStore.save(response.data.tokens)
            return response.data
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func request<Output: Decodable & Sendable>(_ path: String, method: String, body: Data?, contentType: String = "application/json", authenticated: Bool, retryAfterRefresh: Bool, queryItems: [URLQueryItem] = []) async throws -> Output {
        let data: Data
        if method == "GET" {
            data = try await cachedResponseData(
                path,
                authenticated: authenticated,
                retryAfterRefresh: retryAfterRefresh,
                queryItems: queryItems
            )
        } else {
            invalidateResponseCache()
            data = try await validatedRequest(path, method: method, body: body, contentType: body == nil ? nil : contentType, authenticated: authenticated, retryAfterRefresh: retryAfterRefresh, queryItems: queryItems)
        }
        do { return try decoder.decode(Output.self, from: data) } catch { throw APIError.decoding }
    }

    private func cachedResponseData(
        _ path: String,
        authenticated: Bool,
        retryAfterRefresh: Bool,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        let key = responseCacheKey(path: path, queryItems: queryItems)
        let now = ContinuousClock.now
        if let cached = responseCache[key], cached.expiresAt > now {
            return cached.data
        }
        if let task = responseTasks[key] {
            return try await task.value
        }

        let generation = cacheGeneration
        let task = Task<Data, Error> { [self] in
            try await validatedRequest(
                path,
                method: "GET",
                body: nil,
                contentType: nil,
                authenticated: authenticated,
                retryAfterRefresh: retryAfterRefresh,
                queryItems: queryItems
            )
        }
        responseTasks[key] = task
        do {
            let data = try await task.value
            if generation == cacheGeneration {
                responseTasks[key] = nil
                if responseCache.count >= 128 {
                    responseCache = responseCache.filter { $0.value.expiresAt > now }
                    if responseCache.count >= 128,
                       let nextToExpire = responseCache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                        responseCache[nextToExpire] = nil
                    }
                }
                responseCache[key] = CachedResponse(
                    data: data,
                    expiresAt: now.advanced(by: .seconds(15))
                )
            }
            return data
        } catch {
            if generation == cacheGeneration {
                responseTasks[key] = nil
            }
            throw error
        }
    }

    private func responseCacheKey(path: String, queryItems: [URLQueryItem]) -> String {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint.absoluteString
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url?.absoluteString ?? endpoint.absoluteString
    }

    private func invalidateResponseCache() {
        cacheGeneration &+= 1
        responseCache.removeAll(keepingCapacity: true)
        responseTasks.removeAll(keepingCapacity: true)
    }

    private func validatedUpload(
        _ path: String,
        body: Data,
        contentType: String,
        authenticated: Bool,
        retryAfterRefresh: Bool,
        queryItems: [URLQueryItem],
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        if authenticated, let token = try tokenStore.read()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = UploadProgressDelegate(progress: progress)
        progress?(0)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body, delegate: delegate)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            progress?(1)
            return data
        }
        let serverError = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        if http.statusCode == 401 && authenticated && retryAfterRefresh {
            do {
                _ = try await refresh()
            } catch let error as APIError {
                if error.invalidatesSession { try? tokenStore.delete() }
                throw error
            }
            return try await validatedUpload(
                path,
                body: body,
                contentType: contentType,
                authenticated: authenticated,
                retryAfterRefresh: false,
                queryItems: queryItems,
                progress: progress
            )
        }
        if let serverError { throw APIError.server(serverError) }
        if http.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.invalidResponse
    }

    private func validatedRequest(_ path: String, method: String, body: Data?, contentType: String?, authenticated: Bool, retryAfterRefresh: Bool, queryItems: [URLQueryItem] = []) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            urlRequest.httpBody = body
            if let contentType { urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        if authenticated, let token = try tokenStore.read()?.accessToken { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        let serverError = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        if http.statusCode == 401 && authenticated && retryAfterRefresh {
            do {
                _ = try await refresh()
            } catch let error as APIError {
                if error.invalidatesSession { try? tokenStore.delete() }
                throw error
            }
            return try await validatedRequest(path, method: method, body: body, contentType: contentType, authenticated: authenticated, retryAfterRefresh: false, queryItems: queryItems)
        }
        if let serverError { throw APIError.server(serverError) }
        if http.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.invalidResponse
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: (@Sendable (Double) -> Void)?

    init(progress: (@Sendable (Double) -> Void)?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress?(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }
}

struct EmptyResponse: Decodable, Sendable { }
