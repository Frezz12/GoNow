package frezzy.gonow.features.notifications

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.NotificationRepository
import frezzy.gonow.models.*
import kotlinx.coroutines.launch

class NotificationsViewModel(private val repository: NotificationRepository) : ViewModel() {

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
        isLoading = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val feed = repository.getNotifications()
                notifications = feed.items
                unreadCount = feed.unreadCount
            } catch (e: Exception) {
                errorMessage = e.message
            } finally {
                isLoading = false
            }
        }
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
            } catch (_: Exception) {}
        }
    }

    fun markAllRead() {
        viewModelScope.launch {
            try {
                val count = repository.markAllRead()
                notifications = notifications.map { it.copy(isRead = true) }
                unreadCount = count
            } catch (_: Exception) {}
        }
    }

    fun delete(notification: GoNowNotification) {
        viewModelScope.launch {
            try {
                repository.delete(notification.id)
                notifications = notifications.filter { it.id != notification.id }
                if (!notification.isRead) unreadCount = (unreadCount - 1).coerceAtLeast(0)
            } catch (_: Exception) {}
        }
    }
}
