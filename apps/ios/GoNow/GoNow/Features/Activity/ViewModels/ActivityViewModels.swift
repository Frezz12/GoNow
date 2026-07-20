import Combine
import Foundation
import MapKit

@MainActor
final class ActivityCreationViewModel: ObservableObject {
    @Published var draft: ActivityDraft {
        didSet { scheduleAutosave() }
    }
    @Published private(set) var step: ActivityWizardStep = .basics
    @Published private(set) var isRestoring = true
    @Published private(set) var isSubmitting = false
    @Published private(set) var isProcessingPhotos = false
    @Published private(set) var isSearchingLocations = false
    @Published private(set) var isResolvingLocation = false
    @Published private(set) var hasSearchedLocations = false
    @Published private(set) var locationSuggestions: [ActivityLocationSuggestion] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var publishedActivity: GoNowActivity?

    var progress: Double {
        Double(step.rawValue + 1) / Double(ActivityWizardStep.allCases.count)
    }

    var canMoveForward: Bool { validationMessage(for: step) == nil }
    var isLastStep: Bool { step == .preview }
    var titleRemainingCount: Int { max(0, 70 - draft.title.count) }
    var descriptionRemainingCount: Int { max(0, 3_000 - draft.description.count) }

    private let repository: any ActivityRepository
    private let draftStore: ActivityDraftStore
    private let compressor: ActivityPhotoCompressor
    private let locationSearch: ActivityLocationSearchService
    private var autosaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var locationSearchRevision = 0
    private var activeLocationQuery = ""

    init(
        repository: any ActivityRepository,
        draftStore: ActivityDraftStore = ActivityDraftStore(),
        compressor: ActivityPhotoCompressor = ActivityPhotoCompressor(),
        locationSearch: ActivityLocationSearchService? = nil
    ) {
        self.repository = repository
        self.draftStore = draftStore
        self.compressor = compressor
        self.locationSearch = locationSearch ?? ActivityLocationSearchService()
        draft = ActivityDraft()
        self.locationSearch.onSuggestions = { [weak self] query, suggestions in
            guard let self, query == self.activeLocationQuery else { return }
            self.locationSuggestions = suggestions
            self.isSearchingLocations = false
            self.hasSearchedLocations = true
        }
        self.locationSearch.onFailure = { [weak self] query, _ in
            guard let self, query == self.activeLocationQuery else { return }
            self.locationSuggestions = []
            self.isSearchingLocations = false
            self.hasSearchedLocations = true
        }
    }

    func restoreDraft() async {
        defer { isRestoring = false }
        if var restored = await draftStore.load() {
            if restored.visibilityTimingVersion == nil {
                if restored.showTiming == .immediately { restored.showTiming = .atStart }
                restored.visibilityTimingVersion = 2
            }
            restored.additionalQuestions = []
            restored.location?.address = nil
            restored.location?.venueName = nil
            draft = restored
        }
    }

    func moveForward() {
        guard let next = ActivityWizardStep(rawValue: step.rawValue + 1) else { return }
        if let message = validationMessage(for: step) {
            errorMessage = message
            return
        }
        errorMessage = nil
        step = next
        AppHaptics.selection()
    }

    func moveBack() {
        guard let previous = ActivityWizardStep(rawValue: step.rawValue - 1) else { return }
        errorMessage = nil
        step = previous
    }

    func selectStep(_ newStep: ActivityWizardStep) {
        guard newStep.rawValue < step.rawValue else { return }
        errorMessage = nil
        step = newStep
    }

    @discardableResult
    func submit(status: ActivityLifecycleStatus = .published) async -> Bool {
        for candidate in ActivityWizardStep.allCases.dropLast() {
            if let message = validationMessage(for: candidate) {
                step = candidate
                errorMessage = message
                return false
            }
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let activity = try await repository.create(from: draft, status: status)
            publishedActivity = activity
            try? await draftStore.clear()
            AppHaptics.confirmation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addPhotoData(_ data: Data) async {
        guard draft.photos.count < 6 else { return }
        isProcessingPhotos = true
        defer { isProcessingPhotos = false }
        do {
            let compressed = try await compressor.compress(data)
            let isCover = draft.photos.isEmpty
            draft.photos.append(ActivityDraftPhoto(data: compressed, isCover: isCover))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePhoto(id: UUID) {
        guard let index = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        let wasCover = draft.photos[index].isCover
        draft.photos.remove(at: index)
        if wasCover, !draft.photos.isEmpty { draft.photos[0].isCover = true }
    }

    func makeCover(id: UUID) {
        for index in draft.photos.indices { draft.photos[index].isCover = draft.photos[index].id == id }
        guard let selected = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        let photo = draft.photos.remove(at: selected)
        draft.photos.insert(photo, at: 0)
    }

    func movePhoto(id: UUID, direction: Int) {
        guard let source = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(0, source + direction), draft.photos.count - 1)
        guard source != destination else { return }
        draft.photos.swapAt(source, destination)
    }

    func searchLocations(query: String) {
        searchTask?.cancel()
        locationSearchRevision += 1
        let revision = locationSearchRevision
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeLocationQuery = cleanQuery
        locationSuggestions = []
        hasSearchedLocations = false
        locationSearch.clear()
        guard cleanQuery.count >= 2, cleanQuery != draft.location?.address else {
            isSearchingLocations = false
            return
        }
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard let self else { return }
                guard revision == locationSearchRevision else { return }
                isSearchingLocations = true
                let center = draft.location?.coordinate ?? .moscow
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
                )
                locationSearch.updateQuery(cleanQuery, region: region)
            } catch {
                return
            }
        }
    }

    func selectLocation(_ suggestion: ActivityLocationSuggestion) async -> String? {
        searchTask?.cancel()
        locationSearchRevision += 1
        isSearchingLocations = false
        isResolvingLocation = true
        defer { isResolvingLocation = false }
        do {
            let resolved = try await locationSearch.resolve(suggestion)
            guard let coordinate = resolved.coordinate else { return nil }
            draft.location = ActivityLocation(
                coordinate: coordinate,
                address: resolved.displayAddress,
                venueName: draft.location?.venueName,
                visibility: draft.location?.visibility ?? .everyone,
                isExact: true
            )
            activeLocationQuery = ""
            locationSuggestions = []
            hasSearchedLocations = false
            locationSearch.clear()
            return resolved.displayAddress
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func useCoordinate(_ coordinate: MapCoordinate, resolveAddress: Bool = true) async {
        guard coordinate.isValid else { return }
        let address = resolveAddress ? await locationSearch.address(for: coordinate) : nil
        draft.location = ActivityLocation(
            coordinate: coordinate,
            address: address,
            venueName: nil,
            visibility: draft.location?.visibility ?? .everyone,
            isExact: true
        )
    }

    func addQuestion() {
        guard draft.additionalQuestions.count < 3 else { return }
        draft.additionalQuestions.append(ActivityQuestion())
    }

    func dismissError() { errorMessage = nil }

    private func validationMessage(for step: ActivityWizardStep) -> String? {
        switch step {
        case .basics:
            let titleCount = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count
            if !(2...70).contains(titleCount) { return L10n.string("activity.validation.title") }
            if draft.description.count > 3_000 { return L10n.string("activity.validation.description") }
        case .photos:
            if draft.photos.count > 6 { return L10n.string("activity.validation.photos") }
        case .location:
            if draft.location?.coordinate.isValid != true { return L10n.string("activity.validation.location") }
        case .schedule:
            if draft.durationMinutes < 1 || draft.hideAfter <= draft.showAfter {
                return L10n.string("activity.validation.schedule")
            }
        case .participants:
            if draft.participantLimit.map({ $0 < 2 }) == true { return L10n.string("activity.validation.participants") }
            if let min = draft.ageMin, let max = draft.ageMax, min > max { return L10n.string("activity.validation.age") }
        case .preview:
            break
        }
        return nil
    }

    private func scheduleAutosave() {
        guard !isRestoring else { return }
        autosaveTask?.cancel()
        let snapshot = draft
        autosaveTask = Task { [draftStore] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            try? await draftStore.save(snapshot)
        }
    }
}

@MainActor
final class ActivityDetailViewModel: ObservableObject {
    @Published private(set) var activity: GoNowActivity?
    @Published private(set) var coverPhotoData: Data?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published var applicationMessage = ""
    @Published var answers: [UUID: String] = [:]

    let activityID: UUID
    private let repository: any ActivityRepository

    init(activityID: UUID, repository: any ActivityRepository) {
        self.activityID = activityID
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await repository.activity(id: activityID)
            activity = loaded
            errorMessage = nil
            await loadCoverPhoto(for: loaded)
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadCoverPhoto(for activity: GoNowActivity) async {
        coverPhotoData = nil
        guard let photo = activity.photos.first(where: \.isCover) ?? activity.photos.first else { return }
        coverPhotoData = try? await repository.photoData(for: photo)
    }

    func apply() async -> Bool {
        guard let activity else { return false }
        let payload = activity.additionalQuestions.map {
            ActivityApplicationAnswer(questionID: $0.id, value: answers[$0.id, default: ""])
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await repository.apply(
                activityID: activityID,
                message: applicationMessage,
                answers: payload
            )
            self.activity = try await repository.activity(id: activityID)
            AppHaptics.confirmation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func changeStatus(_ status: ActivityLifecycleStatus) async {
        do {
            activity = try await repository.update(id: activityID, changes: ActivityUpdate(status: status))
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleRecruitment() async {
        guard let activity else { return }
        do {
            self.activity = try await repository.update(
                id: activityID,
                changes: ActivityUpdate(recruitmentClosed: !activity.recruitmentClosed)
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func duplicate() async -> GoNowActivity? {
        do { return try await repository.duplicate(activityID: activityID) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
}

@MainActor
final class ActivityApplicationsViewModel: ObservableObject {
    @Published private(set) var applications: [ActivityApplication] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?

    let activityID: UUID
    private let repository: any ActivityRepository

    init(activityID: UUID, repository: any ActivityRepository) {
        self.activityID = activityID
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { applications = try await repository.applications(activityID: activityID); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func decide(_ status: ActivityApplicationStatus, application: ActivityApplication) async {
        processingIDs.insert(application.id)
        defer { processingIDs.remove(application.id) }
        do {
            let updated = try await repository.updateApplication(
                activityID: activityID,
                applicationID: application.id,
                status: status
            )
            if let index = applications.firstIndex(where: { $0.id == updated.id }) { applications[index] = updated }
        } catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
final class OwnedActivitiesViewModel: ObservableObject {
    @Published private(set) var activities: [GoNowActivity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: any ActivityRepository
    init(repository: any ActivityRepository) { self.repository = repository }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { activities = try await repository.ownedActivities(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
