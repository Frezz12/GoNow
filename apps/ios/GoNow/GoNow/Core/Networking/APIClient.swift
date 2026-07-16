import Foundation

enum APIError: LocalizedError, Sendable {
    case server(APIErrorBody)
    case unauthorized
    case invalidResponse
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .server(let error): return error.message
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case .invalidResponse: return "Сервис вернул некорректный ответ."
        case .transport: return "Не удалось подключиться к серверу. Проверьте соединение."
        case .decoding: return "Не удалось обработать ответ сервера."
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

    private func request<Output: Decodable & Sendable>(_ path: String, method: String, body: Data?, authenticated: Bool, retryAfterRefresh: Bool) async throws -> Output {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { urlRequest.httpBody = body; urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated, let token = try tokenStore.read()?.accessToken { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: urlRequest) } catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            do { return try decoder.decode(Output.self, from: data) } catch { throw APIError.decoding }
        }
        let serverError = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        if http.statusCode == 401 && authenticated && retryAfterRefresh {
            do { _ = try await refresh() } catch { try? tokenStore.delete(); throw error }
            return try await request(path, method: method, body: body, authenticated: authenticated, retryAfterRefresh: false)
        }
        if let serverError { throw APIError.server(serverError) }
        if http.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.invalidResponse
    }
}

struct EmptyResponse: Decodable, Sendable { }
