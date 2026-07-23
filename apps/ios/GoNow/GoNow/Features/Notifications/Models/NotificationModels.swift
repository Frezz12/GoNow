import Foundation

enum GoNowNotificationCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case social
    case messages
    case activities
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .social: "Люди"
        case .messages: "Сообщения"
        case .activities: "Активности"
        case .system: "Система"
        }
    }

    var symbol: String {
        switch self {
        case .social: "person.2.fill"
        case .messages: "message.fill"
        case .activities: "figure.run.circle.fill"
        case .system: "bell.fill"
        }
    }
}

struct GoNowNotification: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let actorId: UUID?
    let actorName: String?
    let actorAvatarPath: String?
    let category: GoNowNotificationCategory
    let kind: String
    let title: String
    let body: String
    let entityType: String?
    let entityId: UUID?
    let actionPath: String?
    let payload: NotificationPayload
    var isRead: Bool
    let createdAt: Date

    var destination: NotificationDestination? {
        guard let entityId else { return nil }
        switch entityType {
        case "conversation": return .conversation(entityId, title: actorName ?? "Чат")
        case "activity": return .activity(entityId)
        case "user": return .social
        case "invitation": return .social
        default: return nil
        }
    }
}

struct NotificationPayload: Decodable, Hashable, Sendable {
    let applicationId: UUID?
    let status: String?
    let template: String?

    init(applicationId: UUID? = nil, status: String? = nil, template: String? = nil) {
        self.applicationId = applicationId
        self.status = status
        self.template = template
    }
}

struct NotificationFeed: Decodable, Sendable {
    let items: [GoNowNotification]
    let unreadCount: Int
}

struct NotificationUnreadCount: Decodable, Sendable {
    let unreadCount: Int
}

struct NotificationPreferences: Codable, Equatable, Sendable {
    var pushEnabled: Bool
    var friendRequests: Bool
    var messages: Bool
    var invitations: Bool
    var activities: Bool
    var soundEnabled: Bool
}

struct NotificationRealtimeEvent: Decodable, Sendable {
    let event: String
    let kind: String?
    let recipientId: UUID
    let notificationId: UUID?
    let unreadCount: Int
}

enum NotificationDestination: Hashable, Sendable {
    case conversation(UUID, title: String)
    case activity(UUID)
    case profile(UUID, displayName: String, avatarPath: String?)
    case social
}

struct PushDeviceRegistration: Encodable, Sendable {
    let deviceId: String
    let token: String
    let environment: String
    let appBundle: String
    let locale: String?
}
