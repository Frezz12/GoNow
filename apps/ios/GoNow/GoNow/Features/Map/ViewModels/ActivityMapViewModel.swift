import Combine
import Foundation

@MainActor
final class ActivityMapViewModel: ObservableObject {
    @Published private(set) var activities: [MapActivity] = [] {
        didSet { rebuildVisibleActivities() }
    }
    @Published private(set) var visibleActivities: [MapActivity] = []
    @Published private(set) var state: MapContentState = .initial
    @Published var filters = MapFilterState()
    @Published var selectedActivity: MapActivity?
    @Published var isFilterPresented = false
    @Published var searchQuery = "" {
        didSet {
            rebuildVisibleActivities()
            if let selectedActivity, !visibleActivities.contains(where: { $0.id == selectedActivity.id }) {
                self.selectedActivity = nil
            }
        }
    }
    @Published private(set) var isCreating = false
    @Published private(set) var creationError: String?

    let initialCamera: PersistedMapCamera

    private let repository: any MapActivityRepository
    private let cameraStore: MapCameraStore
    private var loadedBounds: MapBounds?
    private var lastViewport: MapViewport?
    private var loadTask: Task<Void, Never>?
    private var requestGeneration = 0

    init(
        repository: any MapActivityRepository = CachedMapActivityRepository(
            upstream: MockMapActivityRepository(),
            cache: MapActivityPageCache()
        ),
        cameraStore: MapCameraStore = MapCameraStore()
    ) {
        self.repository = repository
        self.cameraStore = cameraStore
        initialCamera = cameraStore.load() ?? PersistedMapCamera(
            center: .europe,
            zoom: 2.2,
            bearing: 0,
            pitch: 0
        )
    }

    func mapBecameIdle(viewport: MapViewport, bearing: Double, pitch: Double, force: Bool = false) {
        lastViewport = viewport
        cameraStore.save(PersistedMapCamera(center: viewport.center, zoom: viewport.zoom, bearing: bearing, pitch: pitch))
        guard force || loadedBounds?.contains(viewport.bounds) != true else { return }
        scheduleLoad(viewport: viewport, debounceNanoseconds: force ? 0 : 400_000_000)
    }

    func reload() {
        guard let viewport = lastViewport else { return }
        loadedBounds = nil
        scheduleLoad(viewport: viewport, debounceNanoseconds: 0)
    }

    func applyFilters(_ newValue: MapFilterState) {
        filters = newValue
        isFilterPresented = false
        reload()
    }

    func selectActivity(id: String) {
        selectedActivity = visibleActivities.first { $0.id == id }
    }

    func createActivity(title: String, category: ActivityCategory, coordinate: MapCoordinate) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 2, coordinate.isValid else { return false }
        isCreating = true
        creationError = nil
        defer { isCreating = false }
        do {
            let created = try await repository.createActivity(CreateMapActivity(
                title: cleanTitle,
                category: category,
                coordinate: coordinate,
                startsAt: nil,
                participantLimit: nil
            ))
            activities = [created] + activities.filter { $0.id != created.id }
            selectedActivity = created
            state = .loaded
            loadedBounds = nil
            return true
        } catch {
            creationError = error.localizedDescription
            return false
        }
    }

    func clearCreationError() {
        creationError = nil
    }

    private func scheduleLoad(viewport: MapViewport, debounceNanoseconds: UInt64) {
        requestGeneration += 1
        let generation = requestGeneration
        loadTask?.cancel()
        let keepsExistingData = !activities.isEmpty
        if !keepsExistingData { state = .loading }
        let repository = repository
        let filters = filters

        loadTask = Task { [weak self] in
            do {
                if debounceNanoseconds > 0 { try await Task.sleep(nanoseconds: debounceNanoseconds) }
                let page = try await repository.activities(in: viewport, filters: filters)
                try Task.checkCancellation()
                guard let self, generation == self.requestGeneration else { return }
                self.activities = page.activities
                if let selectedID = self.selectedActivity?.id {
                    self.selectedActivity = self.visibleActivities.first { $0.id == selectedID }
                }
                self.loadedBounds = page.loadedBounds
                self.state = page.activities.isEmpty ? .empty : .loaded
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.requestGeneration else { return }
                self.state = .failed(
                    message: L10n.string("map.error.loading"),
                    keepsExistingData: keepsExistingData
                )
            }
        }
    }

    private func rebuildVisibleActivities() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            visibleActivities = activities
            return
        }
        visibleActivities = activities.filter { activity in
            activity.title.localizedStandardContains(query)
                || L10n.string(activity.category.titleKey).localizedStandardContains(query)
        }
    }
}

struct MapCameraStore {
    private let defaults: UserDefaults
    private let key = "gonow.map.camera.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> PersistedMapCamera? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PersistedMapCamera.self, from: $0) }
    }

    func save(_ camera: PersistedMapCamera) {
        guard let data = try? JSONEncoder().encode(camera) else { return }
        defaults.set(data, forKey: key)
    }
}
