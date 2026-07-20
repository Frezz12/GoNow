import Foundation
import Combine
import UserNotifications

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
    @Published private(set) var unreadNotificationCount = 0
    @Published private(set) var unreadChatCount = 0

    private let repository: AuthRepository
    private let profileMediaRepository: ProfileMediaRepository
    private let deviceProvider: DeviceIdentityProvider
    private var notificationEventsTask: Task<Void, Never>?
    let socialRepository: SocialRepository
    let notificationRepository: NotificationRepository
    let activityMapRepository: any MapActivityRepository
    let activityRepository: any ActivityRepository

    init(
        repository: AuthRepository,
        profileMediaRepository: ProfileMediaRepository,
        deviceProvider: DeviceIdentityProvider,
        socialRepository: SocialRepository,
        notificationRepository: NotificationRepository,
        activityMapRepository: any MapActivityRepository = MockMapActivityRepository(),
        activityRepository: any ActivityRepository = MockActivityRepository()
    ) {
        self.repository = repository
        self.profileMediaRepository = profileMediaRepository
        self.deviceProvider = deviceProvider
        self.socialRepository = socialRepository
        self.notificationRepository = notificationRepository
        self.activityMapRepository = activityMapRepository
        self.activityRepository = activityRepository
    }

    convenience init() {
        let keychain = KeychainStore()
        let api = APIClient(baseURL: AppConfiguration.apiBaseURL, tokenStore: keychain)
        let deviceProvider = DeviceIdentityProvider(keychain: keychain)
        self.init(
            repository: AuthRepository(api: api, tokenStore: keychain, deviceProvider: deviceProvider),
            profileMediaRepository: ProfileMediaRepository(api: api),
            deviceProvider: deviceProvider,
            socialRepository: SocialRepository(api: api),
            notificationRepository: NotificationRepository(api: api),
            activityMapRepository: CachedMapActivityRepository(
                upstream: MapActivityService(apiClient: api),
                cache: MapActivityPageCache()
            ),
            activityRepository: NetworkActivityRepository(apiClient: api)
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
        sessionError = nil
        do {
            currentUser = try await repository.restore()
            isOptionalProfileNoticeDismissed = false
            restoreProfileSetupState()
            phase = currentUser == nil ? .unauthenticated : .authenticated
            if currentUser != nil {
                await reloadProfileMedia()
            } else {
                await profileMediaRepository.clearCache()
            }
        } catch is CancellationError {
            return
        } catch let error as APIError {
            currentUser = nil
            isOptionalProfileNoticeDismissed = false
            isProfileSetupStarted = false
            if error.invalidatesSession {
                repository.clearSession()
                await profileMediaRepository.clearCache()
                sessionError = nil
                phase = .unauthenticated
            } else {
                sessionError = error.localizedDescription
                phase = .launching
            }
        } catch {
            repository.clearSession()
            await profileMediaRepository.clearCache()
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

    func register(name: String, username: String, email: String, password: String) async throws -> RegistrationData {
        try await repository.register(name: name, username: username, email: email, password: password)
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
        catch {
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
        }
    }

    func updateProfile(_ payload: UpdateProfilePayload) async throws {
        do {
            currentUser = try await repository.updateProfile(payload)
            if currentUser?.profileStatus == .complete {
                isOptionalProfileNoticeDismissed = false
            }
            sessionError = nil
        } catch {
            _ = await invalidateSessionIfNeeded(error)
            throw error
        }
    }

    func usernameAvailability(_ username: String, authenticated: Bool = true) async throws -> UsernameAvailability {
        try await repository.usernameAvailability(username, authenticated: authenticated)
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
            if await invalidateSessionIfNeeded(error) { return }
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
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
            throw error
        }
    }

    func uploadProfilePhoto(_ imageData: Data) async throws {
        do {
            _ = try await profileMediaRepository.uploadPhoto(imageData)
            await reloadProfileMedia()
        } catch {
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
            throw error
        }
    }

    func profilePhotoData(_ photo: ProfilePhoto) async -> Data {
        do {
            return try await profileMediaRepository.content(for: photo)
        } catch {
            _ = await invalidateSessionIfNeeded(error)
            return Data()
        }
    }

    func deleteProfilePhoto(_ photo: ProfilePhoto) async throws {
        do {
            try await profileMediaRepository.delete(photo)
            await reloadProfileMedia()
        } catch {
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
            throw error
        }
    }

    func updateProfilePhotoDescription(_ description: String?, for photo: ProfilePhoto) async throws {
        do {
            let updated = try await profileMediaRepository.updateDescription(description, for: photo)
            profilePhotos = profilePhotos.replacing(updated)
        } catch {
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
            throw error
        }
    }

    func setProfilePhotoLiked(_ liked: Bool, for photo: ProfilePhoto) async throws {
        do {
            let engagement = try await profileMediaRepository.setLiked(liked, for: photo)
            profilePhotos = profilePhotos.replacing(
                photo.updating(likeCount: engagement.likeCount, isLiked: engagement.isLiked)
            )
        } catch {
            if !(await invalidateSessionIfNeeded(error)) { sessionError = error.localizedDescription }
            throw error
        }
    }

    func dismissSessionError() {
        sessionError = nil
    }

    func startNotificationUpdates() {
        guard phase == .authenticated, notificationEventsTask == nil else { return }
        notificationEventsTask = Task { [weak self, notificationRepository] in
            var retryDelay = Duration.seconds(1)
            while !Task.isCancelled {
                do {
                    let events = try await notificationRepository.liveEvents()
                    for try await event in events {
                        guard !Task.isCancelled else { return }
                        retryDelay = .seconds(1)
                        self?.applyUnreadNotificationCount(event.unreadCount)
                        if event.kind == "new_message" {
                            await self?.reloadChatUnreadCount()
                        }
                    }
                } catch is CancellationError {
                    return
                } catch { }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, .seconds(60))
                if self?.phase != .authenticated {
                    return
                }
            }
        }
    }

    func reloadNotificationCount() async {
        guard phase == .authenticated else { return }
        do {
            applyUnreadNotificationCount(try await notificationRepository.unreadCount())
        } catch {
            _ = await invalidateSessionIfNeeded(error)
        }
    }

    func applyUnreadNotificationCount(_ count: Int) {
        let normalized = max(0, count)
        guard unreadNotificationCount != normalized else { return }
        unreadNotificationCount = normalized
        let badge = unreadNotificationCount
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(badge) }
    }

    func reloadChatUnreadCount() async {
        guard phase == .authenticated else { return }
        do {
            let conversations = try await socialRepository.conversations()
            unreadChatCount = conversations.reduce(0) { $0 + max(0, $1.unreadCount) }
        } catch {
            _ = await invalidateSessionIfNeeded(error)
        }
    }

    func applyUnreadChatCount(_ count: Int) {
        unreadChatCount = max(0, count)
    }

    func performPushAction(_ action: PushNotificationAction) async {
        guard phase == .authenticated else { return }
        do {
            switch action.kind {
            case "friend_request":
                _ = try await socialRepository.decideFriend(
                    action.entityID,
                    action: action.decision.rawValue
                )
            case "invitation":
                _ = try await socialRepository.decideInvitation(
                    action.entityID,
                    action: action.decision.rawValue
                )
            case "activity_application":
                guard let applicationID = action.applicationID else { return }
                _ = try await activityRepository.updateApplication(
                    activityID: action.entityID,
                    applicationID: applicationID,
                    status: action.decision == .accept ? .accepted : .rejected
                )
            default:
                return
            }
            await reloadNotificationCount()
            await reloadChatUnreadCount()
        } catch {
            sessionError = error.localizedDescription
        }
    }

    func registerPushToken(_ token: String) async {
        guard phase == .authenticated,
              let bundle = Bundle.main.bundleIdentifier,
              let device = try? deviceProvider.payload() else { return }
#if DEBUG
        let environment = "sandbox"
#else
        let environment = "production"
#endif
        do {
            try await notificationRepository.registerDevice(
                PushDeviceRegistration(
                    deviceId: device.deviceId,
                    token: token,
                    environment: environment,
                    appBundle: bundle,
                    locale: Locale.current.identifier
                )
            )
        } catch {
            _ = await invalidateSessionIfNeeded(error)
        }
    }

    func logout() async {
        if let device = try? deviceProvider.payload() {
            try? await notificationRepository.unregisterDevice(device.deviceId)
        }
        stopNotificationUpdates()
        await repository.logout()
        await profileMediaRepository.clearCache()
        currentUser = nil
        profilePhotos = ProfilePhotos(avatar: nil, photos: [])
        avatarImageData = Data()
        isOptionalProfileNoticeDismissed = false
        isProfileSetupStarted = false
        sessionError = nil
        unreadChatCount = 0
        phase = .unauthenticated
    }

    private func stopNotificationUpdates() {
        notificationEventsTask?.cancel()
        notificationEventsTask = nil
        Task { await notificationRepository.closeLiveEvents() }
        applyUnreadNotificationCount(0)
        unreadChatCount = 0
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

    @discardableResult
    private func invalidateSessionIfNeeded(_ error: Error) async -> Bool {
        guard let apiError = error as? APIError, apiError.invalidatesSession else { return false }
        repository.clearSession()
        await profileMediaRepository.clearCache()
        currentUser = nil
        profilePhotos = ProfilePhotos(avatar: nil, photos: [])
        avatarImageData = Data()
        isOptionalProfileNoticeDismissed = false
        isProfileSetupStarted = false
        sessionError = nil
        phase = .unauthenticated
        stopNotificationUpdates()
        return true
    }
}
