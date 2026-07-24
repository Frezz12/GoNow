package frezzy.gonow.models

import frezzy.gonow.core.AppRoute
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class NotificationCategory(val apiValue: String) {
    SOCIAL("social"), MESSAGES("messages"), ACTIVITIES("activities"), SYSTEM("system");

    val titleRu: String get() = when (this) {
        SOCIAL -> "Люди"
        MESSAGES -> "Сообщения"
        ACTIVITIES -> "Активности"
        SYSTEM -> "Система"
    }

    companion object {
        fun fromApi(value: String) = entries.firstOrNull { it.apiValue == value } ?: SYSTEM
    }
}

@Serializable
data class NotificationPayload(
    @SerialName("applicationId") val applicationId: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("template") val template: String? = null
)

@Serializable
data class GoNowNotification(
    @SerialName("id") val id: String,
    @SerialName("actorId") val actorId: String? = null,
    @SerialName("actorName") val actorName: String? = null,
    @SerialName("actorAvatarPath") val actorAvatarPath: String? = null,
    @SerialName("category") val category: String = "system",
    @SerialName("kind") val kind: String = "",
    @SerialName("title") val title: String,
    @SerialName("body") val body: String,
    @SerialName("entityType") val entityType: String? = null,
    @SerialName("entityId") val entityId: String? = null,
    @SerialName("actionPath") val actionPath: String? = null,
    @SerialName("payload") val payload: NotificationPayload = NotificationPayload(),
    @SerialName("isRead") val isRead: Boolean = false,
    @SerialName("createdAt") val createdAt: String = ""
) {
    val parsedCategory: NotificationCategory get() = NotificationCategory.fromApi(category)

    val destination: NotificationDestination?
        get() = when (entityType) {
            "conversation" -> entityId?.let { NotificationDestination.Conversation(it, actorName ?: title) }
            "activity" -> entityId?.let(NotificationDestination::Activity)
            "user" -> (entityId ?: actorId)?.let(NotificationDestination::User) ?: NotificationDestination.Social
            "invitation" -> NotificationDestination.Social
            else -> when (val route = actionPath?.let(AppRoute::parse)) {
                is AppRoute.ActivityDetail -> NotificationDestination.Activity(route.id)
                is AppRoute.Conversation -> NotificationDestination.Conversation(route.id, route.title)
                is AppRoute.PublicProfile -> NotificationDestination.User(route.id)
                AppRoute.Social -> NotificationDestination.Social
                else -> null
            }
        }
}

sealed interface NotificationDestination {
    data class Conversation(val id: String, val title: String) : NotificationDestination
    data class Activity(val id: String) : NotificationDestination
    data class User(val id: String) : NotificationDestination
    data object Social : NotificationDestination
}

@Serializable
data class NotificationFeed(
    @SerialName("items") val items: List<GoNowNotification> = emptyList(),
    @SerialName("unreadCount") val unreadCount: Int = 0
)

@Serializable
data class NotificationUnreadCount(@SerialName("unreadCount") val unreadCount: Int = 0)

@Serializable
data class NotificationPreferences(
    @SerialName("pushEnabled") val pushEnabled: Boolean = true,
    @SerialName("friendRequests") val friendRequests: Boolean = true,
    @SerialName("messages") val messages: Boolean = true,
    @SerialName("invitations") val invitations: Boolean = true,
    @SerialName("activities") val activities: Boolean = true,
    @SerialName("soundEnabled") val soundEnabled: Boolean = true
)

@Serializable
data class NotificationRealtimeEvent(
    @SerialName("event") val event: String,
    @SerialName("kind") val kind: String? = null,
    @SerialName("recipientId") val recipientId: String,
    @SerialName("notificationId") val notificationId: String? = null,
    @SerialName("unreadCount") val unreadCount: Int = 0
)

enum class NotificationFilter {
    ALL, UNREAD, SOCIAL, MESSAGES, ACTIVITIES;

    val titleRu: String get() = when (this) {
        ALL -> "Все"
        UNREAD -> "Новые"
        SOCIAL -> "Люди"
        MESSAGES -> "Сообщения"
        ACTIVITIES -> "Активности"
    }
}
