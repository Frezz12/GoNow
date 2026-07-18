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
}

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private var refreshTask: Task<AuthData, Error>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func post<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ path: String, body: Input, authenticated: Bool = false, retryAfterRefresh: Bool = true) async throws -> Output {
        let data = try encoder.encode(body)
        return try await request(path, method: "POST", body: data, authenticated: authenticated, retryAfterRefresh: retryAfterRefresh)
    }

    func patch<Input: Encodable & Sendable, Output: Decodable & Sendable>(_ path: String, body: Input) async throws -> Output {
        let data = try encoder.encode(body)
        return try await request(path, method: "PATCH", body: data, authenticated: true, retryAfterRefresh: true)
    }

    func get<Output: Decodable & Sendable>(_ path: String) async throws -> Output {
        try await request(path, method: "GET", body: nil, authenticated: true, retryAfterRefresh: true)
    }

    func uploadImage<Output: Decodable & Sendable>(_ path: String, imageData: Data) async throws -> Output {
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
            retryAfterRefresh: true
        )
    }

    func getData(_ path: String) async throws -> Data {
        try await validatedRequest(path, method: "GET", body: nil, contentType: nil, authenticated: true, retryAfterRefresh: true)
    }

    func delete(_ path: String) async throws {
        _ = try await validatedRequest(path, method: "DELETE", body: nil, contentType: nil, authenticated: true, retryAfterRefresh: true)
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

    private func request<Output: Decodable & Sendable>(_ path: String, method: String, body: Data?, contentType: String = "application/json", authenticated: Bool, retryAfterRefresh: Bool) async throws -> Output {
        let data = try await validatedRequest(path, method: method, body: body, contentType: body == nil ? nil : contentType, authenticated: authenticated, retryAfterRefresh: retryAfterRefresh)
        do { return try decoder.decode(Output.self, from: data) } catch { throw APIError.decoding }
    }

    private func validatedRequest(_ path: String, method: String, body: Data?, contentType: String?, authenticated: Bool, retryAfterRefresh: Bool) async throws -> Data {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
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
        do { (data, response) = try await session.data(for: urlRequest) } catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        let serverError = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        if http.statusCode == 401 && authenticated && retryAfterRefresh {
            do { _ = try await refresh() } catch { try? tokenStore.delete(); throw error }
            return try await validatedRequest(path, method: method, body: body, contentType: contentType, authenticated: authenticated, retryAfterRefresh: false)
        }
        if let serverError { throw APIError.server(serverError) }
        if http.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.invalidResponse
    }
}

struct EmptyResponse: Decodable, Sendable { }
