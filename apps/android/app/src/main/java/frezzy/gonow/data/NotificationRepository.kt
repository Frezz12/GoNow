package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient

class NotificationRepository(private val apiClient: ApiClient) {

    suspend fun getNotifications(): NotificationFeed =
        apiClient.authenticatedRequest { apiClient.api.getNotifications().data }

    suspend fun getUnreadCount(): Int =
        apiClient.authenticatedRequest {
            val response = apiClient.api.getUnreadCount()
            response.data["unreadCount"] ?: 0
        }

    suspend fun markRead(id: String): GoNowNotification =
        apiClient.authenticatedRequest { apiClient.api.markNotificationRead(id).data }

    suspend fun markAllRead(): Int =
        apiClient.authenticatedRequest { apiClient.api.markAllNotificationsRead().data }

    suspend fun delete(id: String) {
        apiClient.authenticatedRequest { apiClient.api.deleteNotification(id) }
    }

    suspend fun getPreferences(): NotificationPreferences =
        apiClient.authenticatedRequest { apiClient.api.getNotificationPreferences().data }

    suspend fun updatePreferences(prefs: NotificationPreferences): NotificationPreferences =
        apiClient.authenticatedRequest { apiClient.api.updateNotificationPreferences(prefs).data }
}
