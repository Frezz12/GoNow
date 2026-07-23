import Foundation

enum SocialPrivacy: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyone
    case friends
    case verified
    case nobody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Все"
        case .friends: "Только друзья"
        case .verified: "Только подтверждённые"
        case .nobody: "Никто"
        }
    }
}

struct SocialPrivacySettings: Codable, Sendable, Equatable {
    let messagePrivacy: SocialPrivacy
    let invitationPrivacy: SocialPrivacy
}

struct SocialUser: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String
    let username: String
    let city: String?
    let bio: String?
    let interests: [String]
    let avatarPath: String?
    let friendshipStatus: String
    let isIncomingRequest: Bool
    let canMessage: Bool
    let canInvite: Bool

    var isFriend: Bool { friendshipStatus == "accepted" }
    var hasPendingRequest: Bool { friendshipStatus == "pending" }
    var initials: String { displayName.initials }
}

struct PublicUserProfile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String
    let username: String
    let age: Int?
    let city: String?
    let occupation: String?
    let relationshipStatus: String?
    let bio: String?
    let interests: [String]
    let languages: [String]
    let availability: String?
    let preferredGroupSize: String?
    let rating: Double
    let distanceKm: Double?

    var initials: String { displayName.initials }

    var preferredGroupSizeText: String? {
        switch preferredGroupSize {
        case "oneToOne": "Один на один"
        case "smallGroup": "Небольшая компания"
        case "largeGroup": "Большая компания"
        case "any": "Любая компания"
        default: nil
        }
    }
}

enum MeetingTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case walk, coffee, cinema, dinner, bicycle, games, concert, talk

    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: "Прогулка"
        case .coffee: "Кофе"
        case .cinema: "Кино"
        case .dinner: "Ужин"
        case .bicycle: "Велопрогулка"
        case .games: "Игры"
        case .concert: "Концерт"
        case .talk: "Поговорить"
        }
    }
    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .coffee: "cup.and.saucer.fill"
        case .cinema: "film.fill"
        case .dinner: "fork.knife"
        case .bicycle: "bicycle"
        case .games: "gamecontroller.fill"
        case .concert: "music.mic"
        case .talk: "bubble.left.and.bubble.right.fill"
        }
    }
}

struct MeetingInvitation: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let senderId: UUID
    let senderName: String
    let recipientId: UUID
    let recipientName: String
    let activityId: UUID?
    let conversationId: UUID?
    let template: String
    let proposedAt: Date?
    let place: String?
    let message: String?
    let status: String
    let expiresAt: Date
    let createdAt: Date
    let isIncoming: Bool

    var templateTitle: String {
        MeetingTemplate(rawValue: template)?.title ?? "Активность"
    }
}

struct Conversation: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let kind: String
    let title: String
    let participantId: UUID?
    let avatarPath: String?
    let activityId: UUID?
    let createdById: UUID?
    let lastMessage: String?
    let lastMessageAt: Date?
    let unreadCount: Int
    let memberCount: Int
    let isArchived: Bool
    let isOnline: Bool
    let lastSeenAt: Date?

    var isGroup: Bool { kind == "group" || kind == "activity" }
    var presenceText: String? {
        guard kind == "direct" else { return "\(memberCount) участников" }
        if isOnline { return "в сети" }
        guard let lastSeenAt else { return nil }
        return Self.lastSeenText(lastSeenAt)
    }

    static func lastSeenText(_ date: Date) -> String {
        let minutes = max(0, Int(Date.now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "был(а) в сети недавно" }
        if minutes < 60 { return "был(а) в сети \(minutes) мин назад" }
        let hours = minutes / 60
        if hours < 24 { return "был(а) в сети \(hours) ч назад" }
        return "был(а) в сети \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct ConversationMember: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String
    let avatarPath: String?
    let isCreator: Bool
    let isFriend: Bool
    let isOnline: Bool
    let lastSeenAt: Date

    var presenceText: String {
        isOnline ? "в сети" : Conversation.lastSeenText(lastSeenAt)
    }
}

struct ConversationDetails: Codable, Sendable, Equatable {
    let conversation: Conversation
    let members: [ConversationMember]
}

struct ConversationInvitation: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let conversationId: UUID
    let conversationTitle: String
    let inviterId: UUID
    let inviterName: String
    let status: String
    let createdAt: Date
}

struct AddConversationMemberResult: Codable, Sendable, Equatable {
    let status: String
}

struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let senderName: String
    let kind: String
    let body: String
    let proposalDetail: String?
    let voteCount: Int
    let isVoted: Bool
    let isMine: Bool
    var isRead: Bool
    let replyToId: UUID?
    let replyToSenderName: String?
    let replyToBody: String?
    let replyToKind: String?
    let attachmentName: String?
    let attachmentContentType: String?
    let attachmentBytes: Int?
    let durationSeconds: Double?
    let contentPath: String?
    let editedAt: Date?
    let createdAt: Date

    var isProposal: Bool { kind == "placeProposal" || kind == "timeProposal" }
    var isInvitation: Bool { kind == "invitation" }
    var isAttachment: Bool { ["image", "video", "file", "audio", "voice"].contains(kind) }
    var canEdit: Bool { isMine && kind == "text" }
    var canDelete: Bool { isMine && kind != "system" && kind != "invitation" }
}

struct ChatRealtimeEvent: Codable, Sendable, Equatable {
    let event: String
    let conversationId: UUID
    let messageId: UUID?
    let userId: UUID?
}

struct CreateInvitationDraft: Sendable {
    let recipientId: UUID
    var template: MeetingTemplate
    var proposedAt: Date?
    var place: String?
    var message: String?
}
