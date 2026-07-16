import Foundation
import Combine

enum AuthenticationPhase: Equatable {
    case launching
    case unauthenticated
    case authenticated
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var phase: AuthenticationPhase = .launching
    @Published private(set) var currentUser: CurrentUser?
    @Published private(set) var isRefreshingUser = false
    @Published private(set) var sessionError: String?

    private let repository: AuthRepository

    init(repository: AuthRepository) { self.repository = repository }

    convenience init() {
        let keychain = KeychainStore()
        self.init(repository: AuthRepository(api: APIClient(baseURL: AppConfiguration.apiBaseURL, tokenStore: keychain), tokenStore: keychain, deviceProvider: DeviceIdentityProvider(keychain: keychain)))
    }

    func restoreSession() async {
        defer { if phase == .launching { phase = currentUser == nil ? .unauthenticated : .authenticated } }
        do {
            currentUser = try await repository.restore()
            phase = currentUser == nil ? .unauthenticated : .authenticated
        } catch {
            repository.clearSession()
            currentUser = nil
            sessionError = nil
            phase = .unauthenticated
        }
    }

    func login(email: String, password: String) async throws {
        let user = try await repository.login(email: email, password: password)
        currentUser = user
        sessionError = nil
        phase = .authenticated
    }

    func register(name: String, email: String, password: String) async throws -> RegistrationData {
        try await repository.register(name: name, email: email, password: password)
    }

    func verifyEmail(email: String, code: String) async throws {
        let user = try await repository.verifyEmail(email: email, code: code)
        currentUser = user
        sessionError = nil
        phase = .authenticated
    }

    func requestPasswordReset(email: String) async throws {
        try await repository.requestPasswordReset(email: email)
    }

    func resetPassword(email: String, code: String, password: String) async throws {
        let user = try await repository.resetPassword(email: email, code: code, password: password)
        currentUser = user
        sessionError = nil
        phase = .authenticated
    }

    func reloadUser() async {
        isRefreshingUser = true
        defer { isRefreshingUser = false }
        do { currentUser = try await repository.currentUser(); sessionError = nil }
        catch { sessionError = error.localizedDescription }
    }

    func updateProfile(_ payload: UpdateProfilePayload) async throws {
        currentUser = try await repository.updateProfile(payload)
        sessionError = nil
    }

    func dismissSessionError() {
        sessionError = nil
    }

    func logout() async {
        await repository.logout()
        currentUser = nil
        sessionError = nil
        phase = .unauthenticated
    }
}
