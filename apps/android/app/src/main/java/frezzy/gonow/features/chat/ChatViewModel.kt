package frezzy.gonow.features.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.models.*
import kotlinx.coroutines.launch

class ChatViewModel(private val repository: SocialRepository) : ViewModel() {

    var conversations by mutableStateOf<List<Conversation>>(emptyList())
        private set

    var invitations by mutableStateOf<List<MeetingInvitation>>(emptyList())
        private set

    var isLoading by mutableStateOf(true)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    val pendingInvitations: List<MeetingInvitation>
        get() = invitations.filter { it.isIncoming && it.status == "pending" }

    fun load() {
        isLoading = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val convResult = repository.getConversations()
                val invResult = repository.getInvitations()
                conversations = convResult
                invitations = invResult
            } catch (e: Exception) {
                errorMessage = e.message
            } finally {
                isLoading = false
            }
        }
    }

    fun createConversation(userId: String, onResult: (Conversation) -> Unit) {
        viewModelScope.launch {
            try {
                val conv = repository.createConversation(userId)
                onResult(conv)
            } catch (e: Exception) {
                errorMessage = e.message
            }
        }
    }
}

class ConversationViewModel(
    private val repository: SocialRepository,
    val conversationId: String,
    val title: String
) : ViewModel() {

    var messages by mutableStateOf<List<ChatMessage>>(emptyList())
        private set

    var draft by mutableStateOf("")
        private set

    var isSending by mutableStateOf(false)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    fun updateDraft(text: String) { draft = text }

    fun load() {
        viewModelScope.launch {
            try {
                messages = repository.getMessages(conversationId)
            } catch (e: Exception) {
                errorMessage = e.message
            }
        }
    }

    fun sendText() {
        val text = draft.trim()
        if (text.isEmpty()) return
        draft = ""
        isSending = true
        viewModelScope.launch {
            try {
                val msg = repository.sendMessage(conversationId, "text", text)
                appendMessage(msg)
            } catch (e: Exception) {
                errorMessage = e.message
            } finally {
                isSending = false
            }
        }
    }

    fun sendProposal(kind: String, body: String, detail: String?) {
        isSending = true
        viewModelScope.launch {
            try {
                val msg = repository.sendMessage(conversationId, kind, body, detail)
                appendMessage(msg)
            } catch (e: Exception) {
                errorMessage = e.message
            } finally {
                isSending = false
            }
        }
    }

    fun vote(message: ChatMessage) {
        if (message.isVoted) return
        viewModelScope.launch {
            try {
                val updated = repository.voteMessage(conversationId, message.id)
                appendMessage(updated)
            } catch (e: Exception) {
                errorMessage = e.message
            }
        }
    }

    private fun appendMessage(msg: ChatMessage) {
        val idx = messages.indexOfFirst { it.id == msg.id }
        if (idx >= 0) {
            messages = messages.toMutableList().apply { set(idx, msg) }
        } else {
            messages = messages + msg
        }
    }

    fun clearError() { errorMessage = null }
}
