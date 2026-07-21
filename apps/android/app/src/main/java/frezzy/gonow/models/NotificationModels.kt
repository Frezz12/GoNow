package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class NotificationCategory(val apiValue: String) {
    SOCIAL("social"), MESSAGES("messages"), ACTIVITIES("activities"), SYSTEM("system");

    val titleRu: String get() = when (this) {
        SOCIAL -> "Люди"; MESSAGES -> "Сообщения"; ACTIVITIES -> "Активности"; SYSTEM -> "Система"
    }
    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: SYSTEM }
}

@Serializable
data class GoNowNotification(
    @SerialName("id") val id: String,
    @SerialName("title") val title: String,
    @SerialName("body") val body: String,
    @SerialName("category") val category: String = "system",
    @SerialName("kind") val kind: String = "",
    @SerialName("actorId") val actorId: String? = null,
    @SerialName("actorName") val actorName: String? = null,
    @SerialName("targetType") val targetType: String? = null,
    @SerialName("targetId") val targetId: String? = null,
    @SerialName("isRead") var isRead: Boolean = false,
    @SerialName("createdAt") val createdAt: String = ""
) {
    val parsedCategory: NotificationCategory get() = NotificationCategory.fromApi(category)
}

@Serializable
data class NotificationFeed(
    @SerialName("items") val items: List<GoNowNotification> = emptyList(),
    @SerialName("unreadCount") val unreadCount: Int = 0
)

@Serializable
data class NotificationPreferences(
    @SerialName("pushEnabled") val pushEnabled: Boolean = true,
    @SerialName("friendRequests") val friendRequests: Boolean = true,
    @SerialName("messages") val messages: Boolean = true,
    @SerialName("invitations") val invitations: Boolean = true,
    @SerialName("activities") val activities: Boolean = true,
    @SerialName("soundEnabled") val soundEnabled: Boolean = true
)

enum class NotificationFilter {
    ALL, UNREAD, SOCIAL, MESSAGES, ACTIVITIES;

    val titleRu: String get() = when (this) {
        ALL -> "Все"; UNREAD -> "Новые"; SOCIAL -> "Люди"; MESSAGES -> "Сообщения"; ACTIVITIES -> "Активности"
    }
}
