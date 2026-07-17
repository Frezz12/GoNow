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
    @Published private(set) var profilePhotos = ProfilePhotos(avatar: nil, photos: [])
    @Published private(set) var avatarImageData = Data()
    @Published private(set) var isOptionalProfileNoticeDismissed = false
    @Published private(set) var isProfileSetupStarted = false

    private let repository: AuthRepository
    private let profileMediaRepository: ProfileMediaRepository

    init(repository: AuthRepository, profileMediaRepository: ProfileMediaRepository) {
        self.repository = repository
        self.profileMediaRepository = profileMediaRepository
    }

    convenience init() {
        let keychain = KeychainStore()
        let api = APIClient(baseURL: AppConfiguration.apiBaseURL, tokenStore: keychain)
        self.init(
            repository: AuthRepository(api: api, tokenStore: keychain, deviceProvider: DeviceIdentityProvider(keychain: keychain)),
            profileMediaRepository: ProfileMediaRepository(api: api)
        )
    }

    var showsProfileCompletionIndicator: Bool {
        guard let status = currentUser?.profileStatus else { return false }
        switch status {
        case .complete:
            return false
        case .optional:
            return !isOptionalProfileNoticeDismissed
        case .required:
            return true
        }
    }

    var shouldShowProfileSetupPrompt: Bool {
        currentUser?.isFreshProfile == true && !isProfileSetupStarted
    }

    func restoreSession() async {
        defer { if phase == .launching { phase = currentUser == nil ? .unauthenticated : .authenticated } }
        do {
            currentUser = try await repository.restore()
            isOptionalProfileNoticeDismissed = false
            restoreProfileSetupState()
            phase = currentUser == nil ? .unauthenticated : .authenticated
            if currentUser != nil { await reloadProfileMedia() }
        } catch {
            repository.clearSession()
            currentUser = nil
            isOptionalProfileNoticeDismissed = false
            isProfileSetupStarted = false
            sessionError = nil
            phase = .unauthenticated
        }
    }

    func login(email: String, password: String) async throws {
        let user = try await repository.login(email: email, password: password)
        currentUser = user
        isOptionalProfileNoticeDismissed = false
        restoreProfileSetupState()
        sessionError = nil
        phase = .authenticated
        await reloadProfileMedia()
    }

    func register(name: String, email: String, password: String) async throws -> RegistrationData {
        try await repository.register(name: name, email: email, password: password)
    }

    func verifyEmail(email: String, code: String) async throws {
        let user = try await repository.verifyEmail(email: email, code: code)
        currentUser = user
        isOptionalProfileNoticeDismissed = false
        restoreProfileSetupState()
        sessionError = nil
        phase = .authenticated
        await reloadProfileMedia()
    }

    func requestPasswordReset(email: String) async throws {
        try await repository.requestPasswordReset(email: email)
    }

    func resetPassword(email: String, code: String, password: String) async throws {
        let user = try await repository.resetPassword(email: email, code: code, password: password)
        currentUser = user
        isOptionalProfileNoticeDismissed = false
        restoreProfileSetupState()
        sessionError = nil
        phase = .authenticated
        await reloadProfileMedia()
    }

    func reloadUser() async {
        isRefreshingUser = true
        defer { isRefreshingUser = false }
        do { currentUser = try await repository.currentUser(); sessionError = nil }
        catch { sessionError = error.localizedDescription }
    }

    func updateProfile(_ payload: UpdateProfilePayload) async throws {
        currentUser = try await repository.updateProfile(payload)
        if currentUser?.profileStatus == .complete {
            isOptionalProfileNoticeDismissed = false
        }
        sessionError = nil
    }

    func dismissOptionalProfileNotice() {
        guard let currentUser, currentUser.profileStatus == .optional else { return }
        isOptionalProfileNoticeDismissed = true
        UserDefaults.standard.set(true, forKey: optionalProfileNoticeStorageKey(for: currentUser))
    }

    func startProfileSetup() {
        guard let currentUser, currentUser.isFreshProfile else { return }
        isProfileSetupStarted = true
        UserDefaults.standard.set(true, forKey: profileSetupStorageKey(for: currentUser))
    }

    func reloadProfileMedia() async {
        guard currentUser != nil else {
            profilePhotos = ProfilePhotos(avatar: nil, photos: [])
            avatarImageData = Data()
            return
        }
        do {
            let media = try await profileMediaRepository.list()
            profilePhotos = media
            avatarImageData = if let avatar = media.avatar {
                try await profileMediaRepository.content(for: avatar)
            } else {
                Data()
            }
        } catch {
            // A missing storage configuration must not end the authenticated session.
            profilePhotos = ProfilePhotos(avatar: nil, photos: [])
            avatarImageData = Data()
        }
    }

    func uploadAvatar(_ imageData: Data) async throws {
        do {
            _ = try await profileMediaRepository.uploadAvatar(imageData)
            await reloadProfileMedia()
        } catch {
            sessionError = error.localizedDescription
            throw error
        }
    }

    func uploadProfilePhoto(_ imageData: Data) async throws {
        do {
            _ = try await profileMediaRepository.uploadPhoto(imageData)
            await reloadProfileMedia()
        } catch {
            sessionError = error.localizedDescription
            throw error
        }
    }

    func profilePhotoData(_ photo: ProfilePhoto) async -> Data {
        (try? await profileMediaRepository.content(for: photo)) ?? Data()
    }

    func deleteProfilePhoto(_ photo: ProfilePhoto) async throws {
        do {
            try await profileMediaRepository.delete(photo)
            await reloadProfileMedia()
        } catch {
            sessionError = error.localizedDescription
            throw error
        }
    }

    func dismissSessionError() {
        sessionError = nil
    }

    func logout() async {
        await repository.logout()
        currentUser = nil
        profilePhotos = ProfilePhotos(avatar: nil, photos: [])
        avatarImageData = Data()
        isOptionalProfileNoticeDismissed = false
        isProfileSetupStarted = false
        sessionError = nil
        phase = .unauthenticated
    }

    private func restoreProfileSetupState() {
        guard let currentUser else {
            isProfileSetupStarted = false
            isOptionalProfileNoticeDismissed = false
            return
        }
        isProfileSetupStarted = UserDefaults.standard.bool(forKey: profileSetupStorageKey(for: currentUser))
        isOptionalProfileNoticeDismissed = UserDefaults.standard.bool(forKey: optionalProfileNoticeStorageKey(for: currentUser))
    }

    private func profileSetupStorageKey(for user: CurrentUser) -> String {
        "gonow.profile.setup.started.\(user.id.uuidString)"
    }

    private func optionalProfileNoticeStorageKey(for user: CurrentUser) -> String {
        "gonow.profile.optional-notice.dismissed.\(user.id.uuidString)"
    }
}
