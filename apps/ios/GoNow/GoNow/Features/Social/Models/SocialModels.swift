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

struct SocialUser: Codable, Identifiable, Sendable, Equatable {
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
    let lastMessage: String?
    let lastMessageAt: Date?
    let unreadCount: Int
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
    let attachmentName: String?
    let attachmentContentType: String?
    let attachmentBytes: Int?
    let durationSeconds: Double?
    let contentPath: String?
    let createdAt: Date

    var isProposal: Bool { kind == "placeProposal" || kind == "timeProposal" }
    var isInvitation: Bool { kind == "invitation" }
    var isAttachment: Bool { ["image", "video", "file", "audio", "voice"].contains(kind) }
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
