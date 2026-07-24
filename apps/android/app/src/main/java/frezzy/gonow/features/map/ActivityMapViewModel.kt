package frezzy.gonow.features.map

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.data.toMapActivityResponse
import frezzy.gonow.data.MapCameraStore
import frezzy.gonow.models.*
import frezzy.gonow.core.throwIfCancellation
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ActivityMapViewModel(
    private val repository: ActivityRepository,
    private val cameraStore: MapCameraStore
) : ViewModel() {

    val initialCamera: PersistedMapCamera? = cameraStore.load()

    var activities by mutableStateOf<List<MapActivityResponse>>(emptyList())
        private set

    var visibleActivities by mutableStateOf<List<MapActivityResponse>>(emptyList())
        private set

    var state by mutableStateOf<MapContentState>(MapContentState.Initial)
        private set

    var filters by mutableStateOf(MapFilterState())
        private set

    var selectedActivity by mutableStateOf<MapActivityResponse?>(null)
        private set

    var searchQuery by mutableStateOf("")
        private set

    var isCreating by mutableStateOf(false)
        private set

    var creationError by mutableStateOf<String?>(null)
        private set

    var mapStyleJson by mutableStateOf<String?>(null)
        private set

    var mapStyleLoading by mutableStateOf(true)
        private set

    var mapStyleError by mutableStateOf<String?>(null)
        private set

    private var loadedBounds: MapBounds? = null
    private var lastViewport: MapViewport? = null
    private var locallyCreatedActivities = emptyMap<String, MapActivityResponse>()
    private var loadJob: Job? = null
    private var requestGeneration = 0

    init {
        loadMapStyle()
    }

    fun mapBecameIdle(viewport: MapViewport, force: Boolean = false) {
        lastViewport = viewport
        saveCameraState(viewport)
        if (!force && loadedBounds?.covers(viewport.bounds) == true) return
        scheduleLoad(viewport, debounceMs = if (force) 0 else 400)
    }

    fun reload() {
        val viewport = lastViewport ?: return
        loadedBounds = null
        scheduleLoad(viewport, debounceMs = 0)
    }

    fun applyFilters(newFilters: MapFilterState) {
        filters = newFilters
        reload()
    }

    fun selectActivity(id: String) {
        selectedActivity = visibleActivities.firstOrNull { it.id == id }
    }

    fun selectExternalActivity(id: String) {
        selectedActivity = activities.firstOrNull { it.id == id }
            ?: MapActivityResponse(
                id = id,
                title = "Активность",
                category = ActivityCategory.OTHER.apiValue,
                coordinate = MapCoordinate(0.0, 0.0)
            )
    }

    fun clearSelection() {
        selectedActivity = null
    }

    fun showCreatedActivity(activity: GoNowActivity, coordinate: MapCoordinate? = null) {
        val created = activity.toMapActivityResponse().let { mapped ->
            coordinate?.takeIf(MapCoordinate::isValid)?.let { mapped.copy(coordinate = it) } ?: mapped
        }
        locallyCreatedActivities = locallyCreatedActivities + (created.id to created)
        activities = (listOf(created) + activities.filter { it.id != created.id })
        rebuildVisibleActivities()
        selectedActivity = created
        state = MapContentState.Loaded
    }

    fun updateSearchQuery(query: String) {
        searchQuery = query
        rebuildVisibleActivities()
        val selected = selectedActivity
        if (selected != null && visibleActivities.none { it.id == selected.id }) {
            selectedActivity = null
        }
    }

    fun createActivity(title: String, category: ActivityCategory, coordinate: MapCoordinate) {
        val cleanTitle = title.trim()
        if (cleanTitle.length < 2 || !coordinate.isValid) return
        isCreating = true
        creationError = null
        viewModelScope.launch {
            try {
                val createdActivity = repository.createActivity(
                    CreateActivityRequest(
                        title = cleanTitle,
                        category = category.apiValue,
                        latitude = coordinate.latitude,
                        longitude = coordinate.longitude
                    )
                )
                val created = createdActivity.toMapActivityResponse()
                activities = listOf(created) + activities.filter { it.id != created.id }
                selectedActivity = created
                state = MapContentState.Loaded
                loadedBounds = null
            } catch (e: Exception) {
                e.throwIfCancellation()
                creationError = e.message
            } finally {
                isCreating = false
            }
        }
    }

    fun clearCreationError() {
        creationError = null
    }

    fun reloadMapStyle() = loadMapStyle()

    private fun loadMapStyle() {
        mapStyleLoading = true
        mapStyleError = null
        viewModelScope.launch {
            try {
            val style = repository.getMapStyleJson()
            mapStyleJson = style
            mapStyleLoading = false
            if (style == null) mapStyleError = "Не удалось загрузить карту"
            } catch (error: Exception) {
                error.throwIfCancellation()
                mapStyleError = error.message ?: "\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u043a\u0430\u0440\u0442\u0443"
            } finally {
                mapStyleLoading = false
            }
        }
    }

    private fun scheduleLoad(viewport: MapViewport, debounceMs: Long) {
        requestGeneration++
        val generation = requestGeneration
        loadJob?.cancel()
        val keepsExistingData = activities.isNotEmpty()
        if (!keepsExistingData) state = MapContentState.Loading
        val repo = repository
        val currentFilters = filters

        loadJob = viewModelScope.launch {
            if (debounceMs > 0) delay(debounceMs)
            try {
                val page = repo.getMapActivities(
                    bounds = viewport.bounds,
                    zoom = viewport.zoom,
                    categories = currentFilters.categories.takeIf { it.isNotEmpty() },
                    onlyAvailable = currentFilters.onlyAvailable,
                    startsFrom = currentFilters.startsWithinHours?.let { java.time.Instant.now().toString() },
                    startsTo = currentFilters.startsWithinHours?.let { java.time.Instant.now().plusSeconds(it * 3_600L).toString() }
                )
                if (generation != requestGeneration) return@launch
                val serverIds = page.activities.mapTo(mutableSetOf()) { it.id }
                locallyCreatedActivities = locallyCreatedActivities.filterKeys { it !in serverIds }
                val localInViewport = locallyCreatedActivities.values.filter { viewport.bounds.contains(it.coordinate) }
                activities = (localInViewport + page.activities).distinctBy { it.id }
                rebuildVisibleActivities()
                selectedActivity?.let { sel ->
                    selectedActivity = visibleActivities.firstOrNull { it.id == sel.id }
                }
                loadedBounds = page.viewport?.let {
                    MapBounds(it.south, it.west, it.north, it.east)
                }
                state = if (page.activities.isEmpty()) MapContentState.Empty else MapContentState.Loaded
            } catch (error: Exception) {
                error.throwIfCancellation()
                if (generation == requestGeneration) {
                    state = MapContentState.Failed
                }
            }
        }
    }

    private fun rebuildVisibleActivities() {
        val query = searchQuery.trim()
        visibleActivities = if (query.isEmpty()) {
            activities
        } else {
            activities.filter { activity ->
                activity.title.contains(query, ignoreCase = true) ||
                    activity.parsedCategory.titleRu.contains(query, ignoreCase = true)
            }
        }
    }

    private fun saveCameraState(viewport: MapViewport) {
        cameraStore.save(viewport)
    }
}

internal fun MapBounds.covers(other: MapBounds): Boolean {
    if (other.south < south || other.north > north) return false
    fun containsLongitude(longitude: Double): Boolean = if (crossesAntimeridian) {
        longitude >= west || longitude <= east
    } else {
        longitude in west..east
    }
    return containsLongitude(other.west) && containsLongitude(other.east) &&
        (!other.crossesAntimeridian || crossesAntimeridian)
}
