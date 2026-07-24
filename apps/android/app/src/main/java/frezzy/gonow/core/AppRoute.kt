package frezzy.gonow.core

import android.net.Uri

sealed interface AppRoute {
    data class ActivityDetail(val id: String) : AppRoute
    data class Conversation(val id: String, val title: String = "Чат") : AppRoute
    data class PublicProfile(val id: String) : AppRoute
    data object Social : AppRoute
    data object Notifications : AppRoute

    companion object {
        fun parse(uri: Uri?): AppRoute? {
            uri ?: return null
            val segments = uri.pathSegments
            return when (uri.host) {
                "activities" -> segments.firstOrNull()?.let(::ActivityDetail)
                "conversations", "chats" -> segments.firstOrNull()?.let { Conversation(it) }
                "users", "people" -> segments.firstOrNull()?.let(::PublicProfile) ?: Social
                "invitations", "social" -> Social
                "notifications" -> Notifications
                else -> null
            }
        }

        fun parse(value: String): AppRoute? = runCatching {
            val uri = java.net.URI(value)
            val id = uri.path.trim('/').substringBefore('/').takeIf(String::isNotBlank)
            when (uri.host) {
                "activities" -> id?.let(::ActivityDetail)
                "conversations", "chats" -> id?.let { Conversation(it) }
                "users", "people" -> id?.let(::PublicProfile) ?: Social
                "invitations", "social" -> Social
                "notifications" -> Notifications
                else -> null
            }
        }.getOrNull()
    }
}
