package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient
import frezzy.gonow.network.RealtimeClient
import frezzy.gonow.models.ApiError
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.mapNotNull

class SocialRepository(
    private val apiClient: ApiClient,
    private val realtimeClient: RealtimeClient? = null
) {

    suspend fun getPrivacy(): SocialPrivacySettings =
        apiClient.authenticatedRequest { apiClient.api.getSocialPrivacy().data }

    suspend fun updatePrivacy(settings: SocialPrivacySettings): SocialPrivacySettings =
        apiClient.authenticatedRequest { apiClient.api.updateSocialPrivacy(settings).data }

    suspend fun getPeople(query: String? = null): List<SocialUser> =
        apiClient.authenticatedRequest { apiClient.api.getPeople(query).data }

    suspend fun getPublicProfile(userId: String): PublicUserProfile =
        apiClient.authenticatedRequest { apiClient.api.getPublicProfile(userId).data }

    suspend fun requestFriend(userId: String): SocialUser =
        apiClient.authenticatedRequest { apiClient.api.requestFriend(mapOf("userId" to userId)).data }

    suspend fun decideFriend(userId: String, action: String): SocialUser =
        apiClient.authenticatedRequest { apiClient.api.decideFriend(userId, mapOf("action" to action)).data }

    suspend fun removeFriend(userId: String): SocialUser =
        apiClient.authenticatedRequest { apiClient.api.removeFriend(userId).data }

    suspend fun getInvitations(): List<MeetingInvitation> =
        apiClient.authenticatedRequest { apiClient.api.getInvitations().data }

    suspend fun createInvitation(request: CreateInvitationRequest): MeetingInvitation =
        apiClient.authenticatedRequest { apiClient.api.createInvitation(request).data }

    suspend fun decideInvitation(id: String, action: String): MeetingInvitation =
        apiClient.authenticatedRequest { apiClient.api.decideInvitation(id, mapOf("action" to action)).data }

    suspend fun getConversations(): List<Conversation> =
        apiClient.authenticatedRequest { apiClient.api.getConversations().data }

    suspend fun createConversation(userId: String): Conversation =
        apiClient.authenticatedRequest { apiClient.api.createConversation(mapOf("userId" to userId)).data }

    suspend fun getMessages(conversationId: String): List<ChatMessage> =
        apiClient.authenticatedRequest { apiClient.api.getMessages(conversationId).data }

    suspend fun getMessage(conversationId: String, messageId: String): ChatMessage =
        apiClient.authenticatedRequest { apiClient.api.getMessage(conversationId, messageId).data }

    suspend fun sendMessage(conversationId: String, kind: String, body: String, detail: String? = null): ChatMessage =
        apiClient.authenticatedRequest {
            val map = mutableMapOf("kind" to kind, "body" to body)
            detail?.let { map["detail"] = it }
            apiClient.api.sendMessage(conversationId, map).data
        }

    suspend fun voteMessage(conversationId: String, messageId: String): ChatMessage =
        apiClient.authenticatedRequest { apiClient.api.voteMessage(conversationId, messageId).data }

    suspend fun uploadAttachment(
        conversationId: String,
        kind: String,
        bytes: ByteArray,
        fileName: String,
        contentType: String,
        durationSeconds: Double? = null
    ): ChatMessage = apiClient.authenticatedRequest {
        apiClient.api.uploadAttachment(
            conversationId = conversationId,
            kind = kind,
            durationSeconds = durationSeconds,
            file = apiClient.createFilePart(bytes, fileName, contentType)
        ).data
    }

    fun liveEvents(conversationId: String): Flow<ChatRealtimeEvent> {
        val realtime = realtimeClient ?: return emptyFlow()
        return realtime.events(livePath(conversationId)).mapNotNull { payload ->
            runCatching { apiClient.json.decodeFromString<ChatRealtimeEvent>(payload) }.getOrNull()
        }
    }

    fun sendTyping(conversationId: String): Boolean =
        realtimeClient?.send(livePath(conversationId), "{\"event\":\"typing\"}") == true

    fun closeLiveEvents(conversationId: String) {
        realtimeClient?.close(livePath(conversationId))
    }

    suspend fun getContentBytes(contentPath: String): ByteArray =
        apiClient.authenticatedRequest {
            val response = apiClient.api.getContent(contentPath.toApiRelativePath())
            if (!response.isSuccessful) throw ApiError.Http(response.code())
            response.body()?.bytes() ?: throw ApiError.Decoding("Empty attachment response")
        }

    private fun livePath(conversationId: String) = "social/conversations/$conversationId/live"
}
