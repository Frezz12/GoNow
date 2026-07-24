package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient
import frezzy.gonow.network.RealtimeClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.mapNotNull

class NotificationRepository(
    private val apiClient: ApiClient,
    private val realtimeClient: RealtimeClient? = null
) {

    suspend fun getNotifications(): NotificationFeed =
        apiClient.authenticatedRequest { apiClient.api.getNotifications().data }

    suspend fun getUnreadCount(): Int =
        apiClient.authenticatedRequest {
            apiClient.api.getUnreadCount().data.unreadCount
        }

    suspend fun markRead(id: String): GoNowNotification =
        apiClient.authenticatedRequest { apiClient.api.markNotificationRead(id).data }

    suspend fun markAllRead(): Int =
        apiClient.authenticatedRequest { apiClient.api.markAllNotificationsRead().data.unreadCount }

    suspend fun delete(id: String) {
        apiClient.authenticatedRequest { apiClient.api.deleteNotification(id) }
    }

    suspend fun getPreferences(): NotificationPreferences =
        apiClient.authenticatedRequest { apiClient.api.getNotificationPreferences().data }

    suspend fun updatePreferences(prefs: NotificationPreferences): NotificationPreferences =
        apiClient.authenticatedRequest { apiClient.api.updateNotificationPreferences(prefs).data }

    fun liveEvents(): Flow<NotificationRealtimeEvent> {
        val realtime = realtimeClient ?: return emptyFlow()
        return realtime.events("notifications/live").mapNotNull { payload ->
            runCatching { apiClient.json.decodeFromString<NotificationRealtimeEvent>(payload) }.getOrNull()
        }
    }

    fun closeLiveEvents() {
        realtimeClient?.close("notifications/live")
    }
}
