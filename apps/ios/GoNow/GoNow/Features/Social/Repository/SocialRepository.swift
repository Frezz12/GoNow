import Foundation

actor SocialRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func privacy() async throws -> SocialPrivacySettings {
        let response: APIEnvelope<SocialPrivacySettings> = try await api.get("social/privacy")
        return response.data
    }

    func updatePrivacy(message: SocialPrivacy, invitation: SocialPrivacy) async throws -> SocialPrivacySettings {
        let response: APIEnvelope<SocialPrivacySettings> = try await api.patch(
            "social/privacy",
            body: UpdatePrivacyPayload(messagePrivacy: message, invitationPrivacy: invitation)
        )
        return response.data
    }

    func people(query: String = "") async throws -> [SocialUser] {
        let response: APIEnvelope<[SocialUser]> = try await api.get(
            "social/people",
            queryItems: query.isEmpty ? [] : [URLQueryItem(name: "q", value: query)]
        )
        return response.data
    }

    func profile(userID: UUID) async throws -> PublicUserProfile {
        let response: APIEnvelope<PublicUserProfile> = try await api.getFresh(
            "users/\(userID.uuidString)"
        )
        return response.data
    }

    func profilePhotos(userID: UUID) async throws -> ProfilePhotos {
        let response: APIEnvelope<ProfilePhotos> = try await api.getFresh(
            "users/\(userID.uuidString)/photos"
        )
        return response.data
    }

    func setPhotoLiked(_ liked: Bool, photoID: UUID) async throws -> PhotoEngagement {
        let path = "users/photos/\(photoID.uuidString)/like"
        let response: APIEnvelope<PhotoEngagement>
        if liked {
            response = try await api.post(
                path,
                body: EmptySocialPayload(),
                authenticated: true
            )
        } else {
            response = try await api.deleteDecodable(path)
        }
        guard response.data.photoId == photoID else { throw APIError.invalidResponse }
        return response.data
    }

    func requestFriend(_ userID: UUID) async throws -> SocialUser {
        let response: APIEnvelope<SocialUser> = try await api.post(
            "social/friends",
            body: TargetUserPayload(userId: userID),
            authenticated: true
        )
        return response.data
    }

    func decideFriend(_ userID: UUID, action: String) async throws -> SocialUser {
        let response: APIEnvelope<SocialUser> = try await api.patch(
            "social/friends/\(userID.uuidString)",
            body: DecisionPayload(action: action)
        )
        return response.data
    }

    func removeFriend(_ userID: UUID) async throws -> SocialUser {
        let response: APIEnvelope<SocialUser> = try await api.deleteDecodable(
            "social/friends/\(userID.uuidString)"
        )
        return response.data
    }

    func invitations() async throws -> [MeetingInvitation] {
        let response: APIEnvelope<[MeetingInvitation]> = try await api.get("social/invitations")
        return response.data
    }

    func createInvitation(_ draft: CreateInvitationDraft) async throws -> MeetingInvitation {
        let payload = CreateInvitationPayload(
            recipientId: draft.recipientId,
            activityId: nil,
            template: draft.template.rawValue,
            proposedAt: draft.proposedAt,
            place: draft.place,
            message: draft.message,
            expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let response: APIEnvelope<MeetingInvitation> = try await api.post(
            "social/invitations",
            body: payload,
            authenticated: true
        )
        return response.data
    }

    func decideInvitation(_ invitationID: UUID, action: String) async throws -> MeetingInvitation {
        let response: APIEnvelope<MeetingInvitation> = try await api.patch(
            "social/invitations/\(invitationID.uuidString)",
            body: DecisionPayload(action: action)
        )
        return response.data
    }

    func conversations() async throws -> [Conversation] {
        let response: APIEnvelope<[Conversation]> = try await api.get("social/conversations")
        return response.data
    }

    func createConversation(with userID: UUID) async throws -> Conversation {
        let response: APIEnvelope<Conversation> = try await api.post(
            "social/conversations",
            body: TargetUserPayload(userId: userID),
            authenticated: true
        )
        return response.data
    }

    func messages(conversationID: UUID) async throws -> [ChatMessage] {
        let response: APIEnvelope<[ChatMessage]> = try await api.getFresh(
            "social/conversations/\(conversationID.uuidString)/messages"
        )
        return response.data
    }

    func message(conversationID: UUID, messageID: UUID) async throws -> ChatMessage {
        let response: APIEnvelope<ChatMessage> = try await api.getFresh(
            "social/conversations/\(conversationID.uuidString)/messages/\(messageID.uuidString)"
        )
        return response.data
    }

    func sendMessage(
        conversationID: UUID,
        kind: String = "text",
        body: String,
        detail: String? = nil
    ) async throws -> ChatMessage {
        let response: APIEnvelope<ChatMessage> = try await api.post(
            "social/conversations/\(conversationID.uuidString)/messages",
            body: SendMessagePayload(kind: kind, body: body, proposalDetail: detail),
            authenticated: true
        )
        return response.data
    }

    func vote(conversationID: UUID, messageID: UUID) async throws -> ChatMessage {
        let response: APIEnvelope<ChatMessage> = try await api.post(
            "social/conversations/\(conversationID.uuidString)/messages/\(messageID.uuidString)/vote",
            body: EmptySocialPayload(),
            authenticated: true
        )
        return response.data
    }

    func uploadAttachment(
        conversationID: UUID,
        kind: String,
        data: Data,
        fileName: String,
        contentType: String,
        duration: Double? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ChatMessage {
        var query = [URLQueryItem(name: "kind", value: kind)]
        if let duration {
            query.append(URLQueryItem(name: "durationSeconds", value: String(duration)))
        }
        let response: APIEnvelope<ChatMessage> = try await api.uploadFile(
            "social/conversations/\(conversationID.uuidString)/attachments",
            data: data,
            fileName: fileName,
            contentType: contentType,
            queryItems: query,
            progress: progress
        )
        if let path = response.data.contentPath {
            await api.cacheData(data, for: path)
        }
        return response.data
    }

    func liveEvents(conversationID: UUID) async throws -> AsyncThrowingStream<ChatRealtimeEvent, Error> {
        try await api.webSocketEvents(livePath(conversationID), as: ChatRealtimeEvent.self)
    }

    func sendTyping(conversationID: UUID) async throws {
        try await api.sendWebSocketCommand(
            livePath(conversationID),
            command: ChatSocketCommand(event: "typing")
        )
    }

    func closeLiveEvents(conversationID: UUID) async {
        await api.closeWebSocket(livePath(conversationID))
    }

    func content(path: String) async throws -> Data {
        try await api.getData(path)
    }

    private func livePath(_ conversationID: UUID) -> String {
        "social/conversations/\(conversationID.uuidString)/live"
    }
}

private struct UpdatePrivacyPayload: Encodable, Sendable {
    let messagePrivacy: SocialPrivacy
    let invitationPrivacy: SocialPrivacy
}

private struct TargetUserPayload: Encodable, Sendable { let userId: UUID }
private struct DecisionPayload: Encodable, Sendable { let action: String }
private struct EmptySocialPayload: Encodable, Sendable { }

private struct CreateInvitationPayload: Encodable, Sendable {
    let recipientId: UUID
    let activityId: UUID?
    let template: String
    let proposedAt: Date?
    let place: String?
    let message: String?
    let expiresAt: Date?
}

private struct SendMessagePayload: Encodable, Sendable {
    let kind: String
    let body: String
    let proposalDetail: String?
}
private struct ChatSocketCommand: Encodable, Sendable { let event: String }
