package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient

class SocialRepository(private val apiClient: ApiClient) {

    suspend fun getPeople(query: String? = null): List<SocialUser> =
        apiClient.authenticatedRequest { apiClient.api.getPeople(query).data }

    suspend fun requestFriend(userId: String) {
        apiClient.authenticatedRequest { apiClient.api.requestFriend(mapOf("userId" to userId)) }
    }

    suspend fun decideFriend(userId: String, action: String) {
        apiClient.authenticatedRequest { apiClient.api.decideFriend(userId, mapOf("action" to action)) }
    }

    suspend fun removeFriend(userId: String) {
        apiClient.authenticatedRequest { apiClient.api.removeFriend(userId) }
    }

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

    suspend fun sendMessage(conversationId: String, kind: String, body: String, detail: String? = null): ChatMessage =
        apiClient.authenticatedRequest {
            val map = mutableMapOf("kind" to kind, "body" to body)
            detail?.let { map["detail"] = it }
            apiClient.api.sendMessage(conversationId, map).data
        }

    suspend fun voteMessage(conversationId: String, messageId: String): ChatMessage =
        apiClient.authenticatedRequest { apiClient.api.voteMessage(conversationId, messageId).data }

    suspend fun getContentBytes(contentPath: String): ByteArray? {
        return try {
            apiClient.authenticatedRequest {
                val response = apiClient.api.getPhotoContent(contentPath.removePrefix("/api/v1/"))
                if (response.isSuccessful) response.body()?.bytes() else null
            }
        } catch (_: Exception) { null }
    }
}
