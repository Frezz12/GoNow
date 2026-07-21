package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SocialUser(
    @SerialName("id") val id: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("username") val username: String = "",
    @SerialName("city") val city: String? = null,
    @SerialName("bio") val bio: String? = null,
    @SerialName("interests") val interests: List<String> = emptyList(),
    @SerialName("avatarPath") val avatarPath: String? = null,
    @SerialName("friendshipStatus") val friendshipStatus: String = "none",
    @SerialName("isIncomingRequest") val isIncomingRequest: Boolean = false,
    @SerialName("canMessage") val canMessage: Boolean = false,
    @SerialName("canInvite") val canInvite: Boolean = false
) {
    val initials: String get() = displayName.split("\\s+".toRegex()).take(2).mapNotNull { it.firstOrNull()?.uppercase() }.joinToString("")
    val isFriend: Boolean get() = friendshipStatus == "accepted"
    val hasPendingRequest: Boolean get() = friendshipStatus == "pending"
}

@Serializable
data class Conversation(
    @SerialName("id") val id: String,
    @SerialName("kind") val kind: String = "direct",
    @SerialName("title") val title: String,
    @SerialName("participantId") val participantId: String? = null,
    @SerialName("avatarPath") val avatarPath: String? = null,
    @SerialName("lastMessage") val lastMessage: String? = null,
    @SerialName("lastMessageAt") val lastMessageAt: String? = null,
    @SerialName("unreadCount") val unreadCount: Int = 0
)

@Serializable
data class ChatMessage(
    @SerialName("id") val id: String,
    @SerialName("conversationId") val conversationId: String = "",
    @SerialName("senderId") val senderId: String,
    @SerialName("senderName") val senderName: String = "",
    @SerialName("kind") val kind: String = "text",
    @SerialName("body") val body: String,
    @SerialName("proposalDetail") val proposalDetail: String? = null,
    @SerialName("voteCount") val voteCount: Int = 0,
    @SerialName("isVoted") val isVoted: Boolean = false,
    @SerialName("isMine") val isMine: Boolean = false,
    @SerialName("attachmentName") val attachmentName: String? = null,
    @SerialName("attachmentContentType") val attachmentContentType: String? = null,
    @SerialName("attachmentBytes") val attachmentBytes: Long? = null,
    @SerialName("durationSeconds") val durationSeconds: Double? = null,
    @SerialName("contentPath") val contentPath: String? = null,
    @SerialName("createdAt") val createdAt: String = ""
) {
    val isProposal: Boolean get() = kind == "placeProposal" || kind == "timeProposal"
    val isAttachment: Boolean get() = kind in listOf("image", "video", "file", "audio", "voice")
}

@Serializable
data class MeetingInvitation(
    @SerialName("id") val id: String,
    @SerialName("senderId") val senderId: String = "",
    @SerialName("senderName") val senderName: String = "",
    @SerialName("recipientId") val recipientId: String = "",
    @SerialName("recipientName") val recipientName: String = "",
    @SerialName("activityId") val activityId: String? = null,
    @SerialName("conversationId") val conversationId: String? = null,
    @SerialName("template") val template: String = "walk",
    @SerialName("proposedAt") val proposedAt: String? = null,
    @SerialName("place") val place: String? = null,
    @SerialName("message") val message: String? = null,
    @SerialName("status") val status: String = "pending",
    @SerialName("expiresAt") val expiresAt: String = "",
    @SerialName("createdAt") val createdAt: String = "",
    @SerialName("isIncoming") val isIncoming: Boolean = false
) {
    val templateTitle: String get() = MeetingTemplate.fromApi(template).titleRu
}

enum class MeetingTemplate(val apiValue: String) {
    WALK("walk"), COFFEE("coffee"), CINEMA("cinema"), DINNER("dinner"),
    BICYCLE("bicycle"), GAMES("games"), CONCERT("concert"), TALK("talk");

    val titleRu: String get() = when (this) {
        WALK -> "Прогулка"; COFFEE -> "Кофе"; CINEMA -> "Кино"; DINNER -> "Ужин"
        BICYCLE -> "Велопрогулка"; GAMES -> "Игры"; CONCERT -> "Концерт"; TALK -> "Поговорить"
    }
    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: WALK }
}

@Serializable
data class CreateInvitationRequest(
    @SerialName("recipientId") val recipientId: String,
    @SerialName("template") val template: String,
    @SerialName("proposedAt") val proposedAt: String? = null,
    @SerialName("place") val place: String? = null,
    @SerialName("message") val message: String? = null
)
