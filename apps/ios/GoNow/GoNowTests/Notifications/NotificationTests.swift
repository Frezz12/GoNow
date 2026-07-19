import XCTest
@testable import GoNow

final class NotificationTests: XCTestCase {
    func testNotificationDecodesAndBuildsConversationDestination() throws {
        let conversationID = UUID()
        let notificationID = UUID()
        let json = """
        {
          "id": "\(notificationID.uuidString)",
          "actorId": null,
          "actorName": "Анна",
          "actorAvatarPath": null,
          "category": "messages",
          "kind": "new_message",
          "title": "Анна",
          "body": "Пойдём гулять?",
          "entityType": "conversation",
          "entityId": "\(conversationID.uuidString)",
          "actionPath": "gonow://chats/\(conversationID.uuidString)",
          "payload": {"messageId": "\(UUID().uuidString)"},
          "isRead": false,
          "createdAt": "2026-07-19T17:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notification = try decoder.decode(GoNowNotification.self, from: Data(json.utf8))

        XCTAssertEqual(notification.id, notificationID)
        XCTAssertEqual(notification.category, .messages)
        XCTAssertEqual(notification.destination, .conversation(conversationID, title: "Анна"))
    }

    func testPushPayloadRoutesToActivity() {
        let activityID = UUID()
        let destination = PushNotificationCoordinator.destination(from: [
            "entityType": "activity",
            "entityId": activityID.uuidString
        ])
        XCTAssertEqual(destination, .activity(activityID))
    }

    func testPushPayloadWithoutEntityIsSafelyIgnored() {
        XCTAssertNil(PushNotificationCoordinator.destination(from: ["kind": "system"]))
    }
}
