import Foundation
import XCTest
@testable import GoNow

final class RichChatTests: XCTestCase {
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
              "attachmentName": "voice.m4a",
              "attachmentContentType": "audio/mp4",
              "attachmentBytes": 1024,
              "durationSeconds": 7.5,
              "contentPath": "social/conversations/2/messages/1/content",
              "createdAt": "2026-07-19T15:00:00Z"
            }
            """.utf8
        ))
        XCTAssertTrue(message.isAttachment)
        XCTAssertEqual(message.durationSeconds, 7.5)
        XCTAssertEqual(message.attachmentContentType, "audio/mp4")

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
