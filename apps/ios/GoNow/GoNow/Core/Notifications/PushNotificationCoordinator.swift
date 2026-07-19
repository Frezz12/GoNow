import Foundation
import Combine
import UIKit
import UserNotifications

final class PushNotificationCoordinator: NSObject, ObservableObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @Published private(set) var deviceToken: String?
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingDestination: NotificationDestination?

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
        let destination = Self.destination(from: response.notification.request.content.userInfo)
        await MainActor.run { pendingDestination = destination }
    }

    static func destination(from payload: [AnyHashable: Any]) -> NotificationDestination? {
        guard let type = payload["entityType"] as? String else { return nil }
        let identifier: UUID? = if let value = payload["entityId"] as? String {
            UUID(uuidString: value)
        } else if let value = payload["entityId"] as? UUID {
            value
        } else {
            nil
        }
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
