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

    func testFriendRequestPushAcceptAction() {
        let userID = UUID()
        let action = PushNotificationCoordinator.action(from: "GONOW_ACCEPT", payload: [
            "kind": "friend_request",
            "entityId": userID.uuidString
        ])

        XCTAssertEqual(action, PushNotificationAction(
            decision: .accept,
            kind: "friend_request",
            entityID: userID,
            applicationID: nil
        ))
    }

    func testActivityApplicationPushCarriesApplicationID() {
        let activityID = UUID()
        let applicationID = UUID()
        let action = PushNotificationCoordinator.action(from: "GONOW_DECLINE", payload: [
            "kind": "activity_application",
            "entityId": activityID.uuidString,
            "notificationPayload": ["applicationId": applicationID.uuidString]
        ])

        XCTAssertEqual(action?.decision, .decline)
        XCTAssertEqual(action?.entityID, activityID)
        XCTAssertEqual(action?.applicationID, applicationID)
    }
}
