package frezzy.gonow.features.notifications

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import frezzy.gonow.data.NotificationRepository
import frezzy.gonow.models.*
import frezzy.gonow.core.throwIfCancellation
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class NotificationsViewModel(private val repository: NotificationRepository) : ViewModel() {

    private var liveJob: Job? = null

    fun start() {
        if (liveJob?.isActive == true) return
        load()
        liveJob = viewModelScope.launch {
            repository.liveEvents().collect { event ->
                unreadCount = event.unreadCount
                refresh(silent = true)
            }
        }
    }

    fun stop() {
        liveJob?.cancel()
        liveJob = null
        repository.closeLiveEvents()
    }

    var notifications by mutableStateOf<List<GoNowNotification>>(emptyList())
        private set

    var filter by mutableStateOf(NotificationFilter.ALL)
        private set

    var isLoading by mutableStateOf(true)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    var unreadCount by mutableStateOf(0)
        private set

    val filteredNotifications: List<GoNowNotification>
        get() = when (filter) {
            NotificationFilter.ALL -> notifications
            NotificationFilter.UNREAD -> notifications.filter { !it.isRead }
            NotificationFilter.SOCIAL -> notifications.filter { it.parsedCategory == NotificationCategory.SOCIAL }
            NotificationFilter.MESSAGES -> notifications.filter { it.parsedCategory == NotificationCategory.MESSAGES }
            NotificationFilter.ACTIVITIES -> notifications.filter { it.parsedCategory == NotificationCategory.ACTIVITIES }
        }

    val todayNotifications: List<GoNowNotification>
        get() = filteredNotifications.filter {
            try {
                java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
                    .parse(it.createdAt)?.let { date ->
                        java.util.Calendar.getInstance().apply { time = date }.get(java.util.Calendar.DAY_OF_YEAR) ==
                            java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
                    } ?: false
            } catch (_: Exception) { false }
        }

    val earlierNotifications: List<GoNowNotification>
        get() = filteredNotifications.filter { it !in todayNotifications }

    fun selectFilter(f: NotificationFilter) { filter = f }

    fun load() {
        refresh(silent = false)
    }

    private fun refresh(silent: Boolean) {
        if (!silent) isLoading = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val feed = repository.getNotifications()
                notifications = feed.items
                unreadCount = feed.unreadCount
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            } finally {
                if (!silent) isLoading = false
            }
        }
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }

    fun markRead(notification: GoNowNotification) {
        if (notification.isRead) return
        viewModelScope.launch {
            try {
                val updated = repository.markRead(notification.id)
                val idx = notifications.indexOfFirst { it.id == updated.id }
                if (idx >= 0) {
                    notifications = notifications.toMutableList().apply { set(idx, updated) }
                }
                unreadCount = (unreadCount - 1).coerceAtLeast(0)
            } catch (error: Exception) {
                error.throwIfCancellation()
                errorMessage = error.message ?: "Не удалось отметить уведомление"
            }
        }
    }

    fun markAllRead() {
        viewModelScope.launch {
            try {
                val count = repository.markAllRead()
                notifications = notifications.map { it.copy(isRead = true) }
                unreadCount = count
            } catch (error: Exception) {
                error.throwIfCancellation()
                errorMessage = error.message ?: "Не удалось отметить уведомления"
            }
        }
    }

    fun delete(notification: GoNowNotification) {
        viewModelScope.launch {
            try {
                repository.delete(notification.id)
                notifications = notifications.filter { it.id != notification.id }
                if (!notification.isRead) unreadCount = (unreadCount - 1).coerceAtLeast(0)
            } catch (error: Exception) {
                error.throwIfCancellation()
                errorMessage = error.message ?: "Не удалось удалить уведомление"
            }
        }
    }
}
