import Foundation

@MainActor
final class AuthRepository {
    private let api: APIClient
    private let tokenStore: TokenStore
    private let deviceProvider: DeviceIdentityProvider

    init(api: APIClient, tokenStore: TokenStore, deviceProvider: DeviceIdentityProvider) {
        self.api = api
        self.tokenStore = tokenStore
        self.deviceProvider = deviceProvider
    }

    func register(name: String, email: String, password: String) async throws -> CurrentUser {
        let response: APIEnvelope<AuthData> = try await api.post("auth/register", body: RegisterPayload(email: email, password: password, displayName: name, device: try deviceProvider.payload()))
        try tokenStore.save(response.data.tokens)
        return response.data.user
    }

    func login(email: String, password: String) async throws -> CurrentUser {
        let response: APIEnvelope<AuthData> = try await api.post("auth/login", body: LoginPayload(email: email, password: password, device: try deviceProvider.payload()))
        try tokenStore.save(response.data.tokens)
        return response.data.user
    }

    func restore() async throws -> CurrentUser? {
        guard let tokens = try tokenStore.read() else { return nil }
        if tokens.accessTokenExpiresAt > Date() {
            let response: APIEnvelope<CurrentUser> = try await api.get("users/me")
            return response.data
        }
        let refreshed = try await api.refresh()
        return refreshed.user
    }

    func currentUser() async throws -> CurrentUser {
        let response: APIEnvelope<CurrentUser> = try await api.get("users/me")
        return response.data
    }

    func logout() async {
        defer { try? tokenStore.delete() }
        guard let tokens = try? tokenStore.read() else { return }
        let _: APIEnvelope<EmptyResponse>? = try? await api.post("auth/logout", body: LogoutPayload(refreshToken: tokens.refreshToken), authenticated: false, retryAfterRefresh: false)
    }

    func clearSession() { try? tokenStore.delete() }
}
