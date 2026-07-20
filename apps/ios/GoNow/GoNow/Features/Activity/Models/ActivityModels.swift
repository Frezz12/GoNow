import Foundation

enum ActivityLifecycleStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case scheduled
    case published
    case full
    case started
    case completed
    case cancelled
    case expired
    case hidden
    case blocked

    var titleKey: String { "activity.status.\(rawValue)" }
}

enum ActivityApplicationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case cancelled
    case expired

    var titleKey: String { "activity.application.status.\(rawValue)" }
}

enum ActivityJoinPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case request
    case instant

    var id: String { rawValue }
    var titleKey: String { "activity.join.\(rawValue)" }
}

enum ActivityLocationVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyone
    case acceptedParticipants = "accepted_participants"
    case oneHourBefore = "one_hour_before"

    var id: String { rawValue }
    var titleKey: String { "activity.location.visibility.\(rawValue)" }
}

enum ActivitySkillLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case beginner
    case intermediate
    case experienced

    var id: String { rawValue }
    var titleKey: String { "activity.skill.\(rawValue)" }
}

enum ActivityCostType: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case fixed
    case selfPaid = "self_paid"
    case estimated

    var id: String { rawValue }
    var titleKey: String { "activity.cost.\(rawValue)" }
}

enum ActivityQuestionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortText = "short_text"
    case yesNo = "yes_no"
    case singleChoice = "single_choice"

    var id: String { rawValue }
    var titleKey: String { "activity.question.kind.\(rawValue)" }
}

enum ActivityDurationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes = "thirty_minutes"
    case oneHour = "one_hour"
    case twoHours = "two_hours"
    case threeHours = "three_hours"
    case allDay = "all_day"
    case custom

    var id: String { rawValue }
    var titleKey: String { "activity.duration.\(rawValue)" }
    var minutes: Int? {
        switch self {
        case .thirtyMinutes: 30
        case .oneHour: 60
        case .twoHours: 120
        case .threeHours: 180
        case .allDay: 1_440
        case .custom: nil
        }
    }
}

enum ActivityShowTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case atStart = "at_start"
    case immediately
    case oneHour = "one_hour"
    case sixHours = "six_hours"
    case oneDay = "one_day"
    case threeDays = "three_days"
    case oneWeek = "one_week"
    case custom

    var id: String { rawValue }
    var titleKey: String { "activity.show.\(rawValue)" }
    var leadTime: TimeInterval? {
        switch self {
        case .atStart: 0
        case .immediately: 0
        case .oneHour: 3_600
        case .sixHours: 21_600
        case .oneDay: 86_400
        case .threeDays: 259_200
        case .oneWeek: 604_800
        case .custom: nil
        }
    }
}

enum ActivityHideTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case afterStart = "after_start"
    case afterEnd = "after_end"
    case oneHourAfterEnd = "one_hour_after_end"
    case custom

    var id: String { rawValue }
    var titleKey: String { "activity.hide.\(rawValue)" }
}

enum ActivityWizardStep: Int, CaseIterable, Identifiable, Sendable {
    case basics
    case photos
    case location
    case schedule
    case participants
    case preview

    var id: Int { rawValue }
    var titleKey: String {
        switch self {
        case .basics: "activity.step.basics"
        case .photos: "activity.step.photos"
        case .location: "activity.step.location"
        case .schedule: "activity.step.schedule"
        case .participants: "activity.step.participants"
        case .preview: "activity.step.preview"
        }
    }
}

enum ActivityLocationMode: String, CaseIterable, Identifiable, Sendable {
    case map
    case current

    var id: String { rawValue }
    var titleKey: String { "activity.location.mode.\(rawValue)" }
}

struct ActivityLocation: Codable, Equatable, Sendable {
    var coordinate: MapCoordinate
    var address: String?
    var venueName: String?
    var visibility: ActivityLocationVisibility
    var isExact: Bool
}

struct ActivityQuestion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: ActivityQuestionKind = .shortText
    var prompt = ""
    var options: [String] = []
    var required = false
}

struct ActivityDraftPhoto: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var data: Data
    var isCover: Bool
}

struct ActivityDraft: Codable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var description = ""
    var category: ActivityCategory = .other
    var photos: [ActivityDraftPhoto] = []
    var location: ActivityLocation?
    var startsAt = Date().addingTimeInterval(3_600)
    var durationPreset: ActivityDurationPreset = .oneHour
    var customDurationMinutes = 60
    var showTiming: ActivityShowTiming = .atStart
    var visibilityTimingVersion: Int? = 2
    var customShowAfter = Date()
    var hideTiming: ActivityHideTiming = .afterEnd
    var customHideAfter = Date().addingTimeInterval(7_200)
    var participantLimit: Int?
    var joinPolicy: ActivityJoinPolicy = .request
    var ageMin: Int?
    var ageMax: Int?
    var languages: [String] = []
    var skillLevel: ActivitySkillLevel = .any
    var costType: ActivityCostType = .free
    var costAmountCents: Int?
    var costNote = ""
    var bringItems: [String] = []
    var rules: [String] = []
    var additionalQuestions: [ActivityQuestion] = []

    var durationMinutes: Int { durationPreset.minutes ?? max(1, customDurationMinutes) }
    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var showAfter: Date {
        guard showTiming != .immediately else { return Date() }
        guard let leadTime = showTiming.leadTime else { return customShowAfter }
        return startsAt.addingTimeInterval(-leadTime)
    }
    var hideAfter: Date {
        switch hideTiming {
        case .afterStart: startsAt
        case .afterEnd: endsAt
        case .oneHourAfterEnd: endsAt.addingTimeInterval(3_600)
        case .custom: customHideAfter
        }
    }
}

struct ActivityPhoto: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let contentPath: String
    let isCover: Bool
    let sortIndex: Int
}

struct GoNowActivity: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let description: String
    let category: ActivityCategory
    let photos: [ActivityPhoto]
    let location: ActivityLocation
    let startsAt: Date
    let durationMinutes: Int
    let showAfter: Date
    let hideAfter: Date?
    let participantCount: Int
    let participantLimit: Int?
    let joinPolicy: ActivityJoinPolicy
    let ageMin: Int?
    let ageMax: Int?
    let languages: [String]
    let skillLevel: ActivitySkillLevel
    let costType: ActivityCostType
    let costAmountCents: Int?
    let costNote: String?
    let bringItems: [String]
    let rules: [String]
    let additionalQuestions: [ActivityQuestion]
    let status: ActivityLifecycleStatus
    let recruitmentClosed: Bool
    let isOrganizer: Bool
    let applicationStatus: ActivityApplicationStatus?
    let canAccessChat: Bool
    let chatConversationID: UUID?

    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var isFull: Bool { participantLimit.map { participantCount >= $0 } ?? false }

    private enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creatorId"
        case title, description, category, photos, location, startsAt, durationMinutes, showAfter, hideAfter
        case participantCount, participantLimit, joinPolicy, ageMin, ageMax, languages, skillLevel
        case costType, costAmountCents, costNote, bringItems, rules, additionalQuestions, status
        case recruitmentClosed, isOrganizer, applicationStatus, canAccessChat
        case chatConversationID = "chatConversationId"
    }
}

struct ActivityApplicant: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let rating: Double
    let organizedActivities: Int
    let avatarURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, displayName, rating, organizedActivities
        case avatarURL = "avatarUrl"
    }
}

struct ActivityApplicationAnswer: Codable, Equatable, Sendable {
    let questionID: UUID
    var value: String

    private enum CodingKeys: String, CodingKey {
        case questionID = "questionId"
        case value
    }
}

struct ActivityApplication: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: UUID
    let applicant: ActivityApplicant
    let status: ActivityApplicationStatus
    let message: String?
    let answers: [ActivityApplicationAnswer]
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activityId"
        case applicant, status, message, answers, createdAt
    }
}

struct ActivityLocationSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let coordinate: MapCoordinate?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        coordinate: MapCoordinate? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
    }

    var displayAddress: String {
        guard !subtitle.isEmpty else { return title }
        guard !subtitle.localizedCaseInsensitiveContains(title) else { return subtitle }
        return "\(title), \(subtitle)"
    }
}

protocol ActivityChatAccessProviding: Sendable {
    func canOpenChat(for activity: GoNowActivity) -> Bool
}

struct ActivityChatAccessService: ActivityChatAccessProviding {
    func canOpenChat(for activity: GoNowActivity) -> Bool { activity.canAccessChat }
}

protocol ActivityPushRegistering: Sendable {
    func register(activityID: UUID, eventTypes: [String]) async throws
}

struct DeferredActivityPushService: ActivityPushRegistering {
    func register(activityID: UUID, eventTypes: [String]) async throws { }
}
