package frezzy.gonow.features.tasks

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.models.GoNowActivity
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

class TasksViewModel(private val repository: ActivityRepository) : ViewModel() {
    var owned by mutableStateOf<List<GoNowActivity>>(emptyList())
        private set
    var participating by mutableStateOf<List<GoNowActivity>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    fun load() {
        if (loading) return
        viewModelScope.launch {
            loading = true
            error = null
            cancellableRunCatching {
                coroutineScope {
                    val ownedRequest = async { repository.getOwnedActivities() }
                    val participatingRequest = async { repository.getParticipatingActivities() }
                    ownedRequest.await() to participatingRequest.await()
                }
            }.onSuccess { (ownedItems, participatingItems) ->
                owned = ownedItems
                participating = participatingItems
            }.onFailure { error = it.message ?: "Не удалось загрузить активности" }
            loading = false
        }
    }
}
