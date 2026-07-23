import Foundation
import XCTest
@testable import GoNow

final class RichChatTests: XCTestCase {
    func testDecodesGroupConversationMetadata() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversation = try decoder.decode(Conversation.self, from: Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "kind": "group",
              "title": "Поход",
              "participantId": null,
              "avatarPath": "social/conversations/1/avatar",
              "activityId": null,
              "createdById": "00000000-0000-0000-0000-000000000002",
              "lastMessage": null,
              "lastMessageAt": null,
              "unreadCount": 2,
              "memberCount": 4,
              "isArchived": true,
              "isOnline": false,
              "lastSeenAt": null
            }
            """.utf8
        ))

        XCTAssertTrue(conversation.isGroup)
        XCTAssertTrue(conversation.isArchived)
        XCTAssertEqual(conversation.presenceText, "4 участников")
    }

    func testDecodesAttachmentMessageAndRealtimeEvent() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "conversationId": "00000000-0000-0000-0000-000000000002",
              "senderId": "00000000-0000-0000-0000-000000000003",
              "senderName": "Анна",
              "kind": "voice",
              "body": "Голосовое сообщение",
              "proposalDetail": null,
              "voteCount": 0,
              "isVoted": false,
              "isMine": false,
              "isRead": false,
              "replyToId": "00000000-0000-0000-0000-000000000004",
              "replyToSenderName": "Иван",
              "replyToBody": "Ты где?",
              "replyToKind": "text",
              "attachmentName": "voice.m4a",
              "attachmentContentType": "audio/mp4",
              "attachmentBytes": 1024,
              "durationSeconds": 7.5,
              "contentPath": "social/conversations/2/messages/1/content",
              "editedAt": null,
              "createdAt": "2026-07-19T15:00:00Z"
            }
            """.utf8
        ))
        XCTAssertTrue(message.isAttachment)
        XCTAssertEqual(message.durationSeconds, 7.5)
        XCTAssertEqual(message.attachmentContentType, "audio/mp4")
        XCTAssertEqual(message.replyToSenderName, "Иван")
        XCTAssertFalse(message.isRead)

        let event = try decoder.decode(ChatRealtimeEvent.self, from: Data(
            """
            {
              "event": "message",
              "conversationId": "00000000-0000-0000-0000-000000000002",
              "messageId": "00000000-0000-0000-0000-000000000001",
              "userId": null
            }
            """.utf8
        ))
        XCTAssertEqual(event.event, "message")
        XCTAssertEqual(event.messageId, message.id)
    }
}
