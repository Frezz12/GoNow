import Foundation

actor NotificationRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(category: GoNowNotificationCategory? = nil, unreadOnly: Bool = false) async throws -> NotificationFeed {
        var query = [URLQueryItem(name: "unreadOnly", value: unreadOnly ? "true" : "false")]
        if let category {
            query.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        let response: APIEnvelope<NotificationFeed> = try await api.get(
            "notifications",
            queryItems: query
        )
        return response.data
    }

    func unreadCount() async throws -> Int {
        let response: APIEnvelope<NotificationUnreadCount> = try await api.get("notifications/unread-count")
        return response.data.unreadCount
    }

    func markRead(_ notificationID: UUID) async throws -> GoNowNotification {
        let response: APIEnvelope<GoNowNotification> = try await api.patch(
            "notifications/\(notificationID.uuidString)/read",
            body: EmptyNotificationPayload()
        )
        return response.data
    }

    func markAllRead() async throws -> Int {
        let response: APIEnvelope<NotificationUnreadCount> = try await api.post(
            "notifications/read-all",
            body: EmptyNotificationPayload(),
            authenticated: true
        )
        return response.data.unreadCount
    }

    func delete(_ notificationID: UUID) async throws {
        try await api.delete("notifications/\(notificationID.uuidString)")
    }

    func preferences() async throws -> NotificationPreferences {
        let response: APIEnvelope<NotificationPreferences> = try await api.get("notifications/settings")
        return response.data
    }

    func updatePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        let response: APIEnvelope<NotificationPreferences> = try await api.patch(
            "notifications/settings",
            body: preferences
        )
        return response.data
    }

    func registerDevice(_ registration: PushDeviceRegistration) async throws {
        try await api.postNoContent("notifications/devices", body: registration)
    }

    func unregisterDevice(_ deviceID: String) async throws {
        try await api.delete("notifications/devices/\(deviceID)")
    }

    func liveEvents() async throws -> AsyncThrowingStream<NotificationRealtimeEvent, Error> {
        try await api.webSocketEvents("notifications/live", as: NotificationRealtimeEvent.self)
    }

    func closeLiveEvents() async {
        await api.closeWebSocket("notifications/live")
    }
}

private struct EmptyNotificationPayload: Encodable, Sendable {}
