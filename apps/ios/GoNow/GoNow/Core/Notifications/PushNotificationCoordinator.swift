import Foundation
import Combine
import UIKit
import UserNotifications

struct PushNotificationAction: Equatable, Sendable {
    enum Decision: String, Sendable {
        case accept
        case decline
    }

    let decision: Decision
    let kind: String
    let entityID: UUID
    let applicationID: UUID?
}

final class PushNotificationCoordinator: NSObject, ObservableObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @Published private(set) var deviceToken: String?
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingDestination: NotificationDestination?
    @Published var pendingAction: PushNotificationAction?

    private enum ActionIdentifier {
        static let accept = "GONOW_ACCEPT"
        static let decline = "GONOW_DECLINE"
    }

    private var remotePushEnabled: Bool {
#if DEBUG
        false
#else
        true
#endif
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerActionCategories()
        Task { await refreshAuthorizationStatus() }
        return true
    }

    @MainActor
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
                if granted, remotePushEnabled {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                authorizationStatus = .denied
            }
        case .authorized, .provisional, .ephemeral:
            if remotePushEnabled {
                UIApplication.shared.registerForRemoteNotifications()
            }
        case .denied:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func consumePendingDestination() {
        pendingDestination = nil
    }

    func consumePendingAction() {
        pendingAction = nil
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        deviceToken = nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .badge, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = response.notification.request.content.userInfo
        if let action = Self.action(from: response.actionIdentifier, payload: payload) {
            await MainActor.run { pendingAction = action }
        } else {
            let destination = Self.destination(from: payload)
            await MainActor.run { pendingDestination = destination }
        }
    }

    private func registerActionCategories() {
        let accept = UNNotificationAction(
            identifier: ActionIdentifier.accept,
            title: "Принять",
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: ActionIdentifier.decline,
            title: "Отклонить",
            options: [.foreground, .destructive]
        )
        let categories = [
            "GONOW_FRIEND_REQUEST",
            "GONOW_INVITATION",
            "GONOW_ACTIVITY_APPLICATION"
        ].map {
            UNNotificationCategory(
                identifier: $0,
                actions: [accept, decline],
                intentIdentifiers: [],
                options: []
            )
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    static func action(
        from identifier: String,
        payload: [AnyHashable: Any]
    ) -> PushNotificationAction? {
        let decision: PushNotificationAction.Decision
        switch identifier {
        case ActionIdentifier.accept: decision = .accept
        case ActionIdentifier.decline: decision = .decline
        default: return nil
        }
        guard let kind = payload["kind"] as? String,
              let entityID = uuid(payload["entityId"]) else { return nil }
        let notificationPayload = payload["notificationPayload"] as? [String: Any]
        return PushNotificationAction(
            decision: decision,
            kind: kind,
            entityID: entityID,
            applicationID: uuid(notificationPayload?["applicationId"])
        )
    }

    private static func uuid(_ value: Any?) -> UUID? {
        if let value = value as? UUID { return value }
        if let value = value as? String { return UUID(uuidString: value) }
        return nil
    }

    static func destination(from payload: [AnyHashable: Any]) -> NotificationDestination? {
        guard let type = payload["entityType"] as? String else { return nil }
        let identifier = uuid(payload["entityId"])
        switch type {
        case "conversation":
            guard let identifier else { return nil }
            return .conversation(identifier, title: "Чат")
        case "activity":
            guard let identifier else { return nil }
            return .activity(identifier)
        case "user", "invitation":
            return .social
        default:
            return nil
        }
    }
}
