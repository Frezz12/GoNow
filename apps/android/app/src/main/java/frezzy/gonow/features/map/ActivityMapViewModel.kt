package frezzy.gonow.features.map

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.models.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ActivityMapViewModel(private val repository: ActivityRepository) : ViewModel() {

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

    private var loadedBounds: MapBounds? = null
    private var lastViewport: MapViewport? = null
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

    fun clearSelection() {
        selectedActivity = null
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
                val created = repository.createActivity(
                    CreateActivityRequest(
                        title = cleanTitle,
                        category = category.apiValue,
                        latitude = coordinate.latitude,
                        longitude = coordinate.longitude
                    )
                )
                activities = listOf(created) + activities.filter { it.id != created.id }
                selectedActivity = created
                state = MapContentState.Loaded
                loadedBounds = null
            } catch (e: Exception) {
                creationError = e.message
            } finally {
                isCreating = false
            }
        }
    }

    fun clearCreationError() {
        creationError = null
    }

    private fun loadMapStyle() {
        viewModelScope.launch {
            mapStyleJson = repository.getMapStyleJson()
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
                    onlyAvailable = currentFilters.onlyAvailable
                )
                if (generation != requestGeneration) return@launch
                activities = page.activities
                selectedActivity?.let { sel ->
                    selectedActivity = visibleActivities.firstOrNull { it.id == sel.id }
                }
                loadedBounds = page.viewport?.let {
                    MapBounds(it.south, it.west, it.north, it.east)
                }
                state = if (page.activities.isEmpty()) MapContentState.Empty else MapContentState.Loaded
            } catch (_: Exception) {
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
        // Persist to SharedPreferences in a real app; for now just in-memory
    }
}

internal fun MapBounds.covers(other: MapBounds): Boolean {
    return other.south >= south && other.north <= north && other.west >= west && other.east <= east
}
