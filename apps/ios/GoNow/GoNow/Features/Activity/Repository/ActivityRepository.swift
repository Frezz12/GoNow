import Foundation

protocol ActivityRepository: Sendable {
    func create(from draft: ActivityDraft, status: ActivityLifecycleStatus) async throws -> GoNowActivity
    func activity(id: UUID) async throws -> GoNowActivity
    func ownedActivities() async throws -> [GoNowActivity]
    func participatingActivities() async throws -> [GoNowActivity]
    func update(id: UUID, changes: ActivityUpdate) async throws -> GoNowActivity
    func apply(activityID: UUID, message: String?, answers: [ActivityApplicationAnswer]) async throws -> ActivityApplication
    func applications(activityID: UUID) async throws -> [ActivityApplication]
    func updateApplication(activityID: UUID, applicationID: UUID, status: ActivityApplicationStatus) async throws -> ActivityApplication
    func duplicate(activityID: UUID) async throws -> GoNowActivity
    func photoData(for photo: ActivityPhoto) async throws -> Data
}

enum ActivityRepositoryError: LocalizedError, Sendable {
    case invalidDraft
    case activityNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDraft: L10n.string("activity.error.invalid_draft")
        case .activityNotFound: L10n.string("activity.error.not_found")
        }
    }
}

struct ActivityUpdate: Encodable, Sendable {
    var description: String?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var venueName: String?
    var startsAt: Date?
    var durationMinutes: Int?
    var participantLimit: Int?
    var recruitmentClosed: Bool?
    var status: ActivityLifecycleStatus?

    init(
        description: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        venueName: String? = nil,
        startsAt: Date? = nil,
        durationMinutes: Int? = nil,
        participantLimit: Int? = nil,
        recruitmentClosed: Bool? = nil,
        status: ActivityLifecycleStatus? = nil
    ) {
        self.description = description
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.venueName = venueName
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.participantLimit = participantLimit
        self.recruitmentClosed = recruitmentClosed
        self.status = status
    }
}

struct NetworkActivityRepository: ActivityRepository {
    let apiClient: APIClient

    func create(from draft: ActivityDraft, status: ActivityLifecycleStatus) async throws -> GoNowActivity {
        guard let location = draft.location else { throw ActivityRepositoryError.invalidDraft }
        let createStatus: ActivityLifecycleStatus = draft.photos.isEmpty ? status : .draft
        let payload = CreateActivityPayload(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            address: nil,
            venueName: nil,
            locationVisibility: location.visibility,
            startsAt: draft.startsAt,
            durationMinutes: draft.durationMinutes,
            showAfter: draft.showAfter,
            hideAfter: draft.hideAfter,
            participantLimit: draft.participantLimit,
            joinPolicy: draft.joinPolicy,
            ageMin: draft.ageMin,
            ageMax: draft.ageMax,
            languages: draft.languages,
            skillLevel: draft.skillLevel,
            costType: draft.costType,
            costAmountCents: draft.costAmountCents,
            costNote: draft.costNote.nilIfEmpty,
            bringItems: draft.bringItems,
            rules: draft.rules,
            additionalQuestions: [],
            status: createStatus
        )
        let envelope: APIEnvelope<GoNowActivity> = try await apiClient.post(
            "activities",
            body: payload,
            authenticated: true
        )
        let created = envelope.data
        guard !draft.photos.isEmpty else { return created }

        for (index, photo) in draft.photos.prefix(6).enumerated() {
            let _: APIEnvelope<ActivityPhoto> = try await apiClient.uploadImage(
                "activities/\(created.id.uuidString)/photos",
                imageData: photo.data,
                queryItems: [
                    URLQueryItem(name: "sortIndex", value: String(index)),
                    URLQueryItem(name: "isCover", value: String(photo.isCover))
                ]
            )
        }
        if status != .draft {
            _ = try await update(id: created.id, changes: ActivityUpdate(status: status))
        }
        return try await activity(id: created.id)
    }

    func activity(id: UUID) async throws -> GoNowActivity {
        let envelope: APIEnvelope<GoNowActivity> = try await apiClient.get("activities/\(id.uuidString)")
        return envelope.data
    }

    func ownedActivities() async throws -> [GoNowActivity] {
        let envelope: APIEnvelope<[GoNowActivity]> = try await apiClient.get("activities/mine")
        return envelope.data
    }

    func participatingActivities() async throws -> [GoNowActivity] {
        let envelope: APIEnvelope<[GoNowActivity]> = try await apiClient.get("activities/participating")
        return envelope.data
    }

    func update(id: UUID, changes: ActivityUpdate) async throws -> GoNowActivity {
        let envelope: APIEnvelope<GoNowActivity> = try await apiClient.patch(
            "activities/\(id.uuidString)",
            body: changes
        )
        return envelope.data
    }

    func apply(activityID: UUID, message: String?, answers: [ActivityApplicationAnswer]) async throws -> ActivityApplication {
        let envelope: APIEnvelope<ActivityApplication> = try await apiClient.post(
            "activities/\(activityID.uuidString)/applications",
            body: CreateApplicationPayload(message: message?.nilIfEmpty, answers: answers),
            authenticated: true
        )
        return envelope.data
    }

    func applications(activityID: UUID) async throws -> [ActivityApplication] {
        let envelope: APIEnvelope<[ActivityApplication]> = try await apiClient.get(
            "activities/\(activityID.uuidString)/applications"
        )
        return envelope.data
    }

    func updateApplication(activityID: UUID, applicationID: UUID, status: ActivityApplicationStatus) async throws -> ActivityApplication {
        let envelope: APIEnvelope<ActivityApplication> = try await apiClient.patch(
            "activities/\(activityID.uuidString)/applications/\(applicationID.uuidString)",
            body: UpdateApplicationPayload(status: status)
        )
        return envelope.data
    }

    func duplicate(activityID: UUID) async throws -> GoNowActivity {
        let envelope: APIEnvelope<GoNowActivity> = try await apiClient.post(
            "activities/\(activityID.uuidString)/duplicate",
            body: EmptyActivityPayload(),
            authenticated: true
        )
        return envelope.data
    }

    func photoData(for photo: ActivityPhoto) async throws -> Data {
        try await apiClient.getData(photo.contentPath)
    }
}

private struct CreateActivityPayload: Encodable, Sendable {
    let title: String
    let description: String
    let category: ActivityCategory
    let latitude: Double
    let longitude: Double
    let address: String?
    let venueName: String?
    let locationVisibility: ActivityLocationVisibility
    let startsAt: Date
    let durationMinutes: Int
    let showAfter: Date
    let hideAfter: Date
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
}

private struct CreateApplicationPayload: Encodable, Sendable {
    let message: String?
    let answers: [ActivityApplicationAnswer]
}

private struct UpdateApplicationPayload: Encodable, Sendable {
    let status: ActivityApplicationStatus
}

private struct EmptyActivityPayload: Encodable, Sendable { }

actor MockActivityRepository: ActivityRepository {
    private let organizerID = UUID()
    private var activitiesByID: [UUID: GoNowActivity] = [:]
    private var applicationsByActivity: [UUID: [ActivityApplication]] = [:]
    private var photoDataByPath: [String: Data] = [:]

    func create(from draft: ActivityDraft, status: ActivityLifecycleStatus) async throws -> GoNowActivity {
        guard let location = draft.location else { throw ActivityRepositoryError.invalidDraft }
        let activityID = UUID()
        var photos: [ActivityPhoto] = []
        for (index, draftPhoto) in draft.photos.prefix(6).enumerated() {
            let path = "mock/activities/\(activityID.uuidString)/photos/\(draftPhoto.id.uuidString)"
            photoDataByPath[path] = draftPhoto.data
            photos.append(ActivityPhoto(
                id: draftPhoto.id,
                contentPath: path,
                isCover: draftPhoto.isCover,
                sortIndex: index
            ))
        }
        let activity = GoNowActivity(
            id: activityID,
            creatorID: organizerID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            photos: photos,
            location: location,
            startsAt: draft.startsAt,
            durationMinutes: draft.durationMinutes,
            showAfter: draft.showAfter,
            hideAfter: draft.hideAfter,
            participantCount: 1,
            participantLimit: draft.participantLimit,
            joinPolicy: draft.joinPolicy,
            ageMin: draft.ageMin,
            ageMax: draft.ageMax,
            languages: draft.languages,
            skillLevel: draft.skillLevel,
            costType: draft.costType,
            costAmountCents: draft.costAmountCents,
            costNote: draft.costNote.nilIfEmpty,
            bringItems: draft.bringItems,
            rules: draft.rules,
            additionalQuestions: [],
            status: status,
            recruitmentClosed: false,
            isOrganizer: true,
            applicationStatus: nil,
            canAccessChat: true,
            chatConversationID: UUID()
        )
        activitiesByID[activity.id] = activity
        return activity
    }

    func activity(id: UUID) async throws -> GoNowActivity {
        guard let activity = activitiesByID[id] else { throw ActivityRepositoryError.activityNotFound }
        return activity
    }

    func ownedActivities() async throws -> [GoNowActivity] {
        activitiesByID.values.filter(\.isOrganizer).sorted { $0.startsAt < $1.startsAt }
    }

    func participatingActivities() async throws -> [GoNowActivity] {
        activitiesByID.values
            .filter { !$0.isOrganizer && $0.applicationStatus == .accepted }
            .sorted { $0.startsAt > $1.startsAt }
    }

    func update(id: UUID, changes: ActivityUpdate) async throws -> GoNowActivity {
        guard let old = activitiesByID[id] else { throw ActivityRepositoryError.activityNotFound }
        let coordinate = MapCoordinate(
            latitude: changes.latitude ?? old.location.coordinate.latitude,
            longitude: changes.longitude ?? old.location.coordinate.longitude
        )
        let updated = GoNowActivity(
            id: old.id, creatorID: old.creatorID, title: old.title,
            description: changes.description ?? old.description, category: old.category,
            photos: old.photos,
            location: ActivityLocation(
                coordinate: coordinate,
                address: changes.address ?? old.location.address,
                venueName: changes.venueName ?? old.location.venueName,
                visibility: old.location.visibility,
                isExact: old.location.isExact
            ),
            startsAt: changes.startsAt ?? old.startsAt,
            durationMinutes: changes.durationMinutes ?? old.durationMinutes,
            showAfter: old.showAfter, hideAfter: old.hideAfter,
            participantCount: old.participantCount,
            participantLimit: changes.participantLimit ?? old.participantLimit,
            joinPolicy: old.joinPolicy, ageMin: old.ageMin, ageMax: old.ageMax,
            languages: old.languages, skillLevel: old.skillLevel, costType: old.costType,
            costAmountCents: old.costAmountCents, costNote: old.costNote,
            bringItems: old.bringItems, rules: old.rules,
            additionalQuestions: old.additionalQuestions,
            status: changes.status ?? old.status,
            recruitmentClosed: changes.recruitmentClosed ?? old.recruitmentClosed,
            isOrganizer: old.isOrganizer, applicationStatus: old.applicationStatus,
            canAccessChat: old.canAccessChat,
            chatConversationID: old.chatConversationID
        )
        activitiesByID[id] = updated
        return updated
    }

    func apply(activityID: UUID, message: String?, answers: [ActivityApplicationAnswer]) async throws -> ActivityApplication {
        guard let activity = activitiesByID[activityID] else { throw ActivityRepositoryError.activityNotFound }
        let application = ActivityApplication(
            id: UUID(), activityID: activityID,
            applicant: ActivityApplicant(
                id: UUID(), displayName: L10n.string("activity.mock.applicant"),
                rating: 5, organizedActivities: 0, avatarURL: nil
            ),
            status: activity.joinPolicy == .instant ? .accepted : .pending,
            message: message?.nilIfEmpty, answers: answers, createdAt: Date()
        )
        applicationsByActivity[activityID, default: []].insert(application, at: 0)
        return application
    }

    func applications(activityID: UUID) async throws -> [ActivityApplication] {
        applicationsByActivity[activityID, default: []]
    }

    func updateApplication(activityID: UUID, applicationID: UUID, status: ActivityApplicationStatus) async throws -> ActivityApplication {
        guard let index = applicationsByActivity[activityID]?.firstIndex(where: { $0.id == applicationID }),
              let current = applicationsByActivity[activityID]?[index] else {
            throw ActivityRepositoryError.activityNotFound
        }
        let updated = ActivityApplication(
            id: current.id, activityID: current.activityID, applicant: current.applicant,
            status: status, message: current.message, answers: current.answers, createdAt: current.createdAt
        )
        applicationsByActivity[activityID]?[index] = updated
        return updated
    }

    func duplicate(activityID: UUID) async throws -> GoNowActivity {
        guard let source = activitiesByID[activityID] else { throw ActivityRepositoryError.activityNotFound }
        let copy = GoNowActivity(
            id: UUID(), creatorID: source.creatorID, title: source.title,
            description: source.description, category: source.category, photos: source.photos,
            location: source.location,
            startsAt: Date(), durationMinutes: source.durationMinutes, showAfter: Date(), hideAfter: nil,
            participantCount: 1, participantLimit: source.participantLimit,
            joinPolicy: source.joinPolicy, ageMin: source.ageMin, ageMax: source.ageMax,
            languages: source.languages, skillLevel: source.skillLevel, costType: source.costType,
            costAmountCents: source.costAmountCents, costNote: source.costNote,
            bringItems: source.bringItems, rules: source.rules,
            additionalQuestions: source.additionalQuestions, status: .draft,
            recruitmentClosed: false, isOrganizer: true, applicationStatus: nil, canAccessChat: true,
            chatConversationID: UUID()
        )
        activitiesByID[copy.id] = copy
        return copy
    }

    func photoData(for photo: ActivityPhoto) async throws -> Data {
        guard let data = photoDataByPath[photo.contentPath] else {
            throw ActivityRepositoryError.activityNotFound
        }
        return data
    }
}
