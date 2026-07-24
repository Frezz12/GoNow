package frezzy.gonow.features.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.core.MediaCache
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.core.throwIfCancellation
import frezzy.gonow.models.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job

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
                e.throwIfCancellation()
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
                e.throwIfCancellation()
                errorMessage = e.message
            }
        }
    }
}

class ConversationViewModel(
    private val repository: SocialRepository,
    private val mediaCache: MediaCache,
    val conversationId: String,
    val title: String
) : AutoCloseable {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var typingClearJob: Job? = null
    private var typingSendJob: Job? = null

    init {
        scope.launch {
            repository.liveEvents(conversationId).collect { event ->
                when (event.event) {
                    "message" -> event.messageId?.let { messageId ->
                        cancellableRunCatching { repository.getMessage(conversationId, messageId) }
                            .onSuccess(::appendMessage)
                    }
                    "typing" -> {
                        typingUserId = event.userId
                        typingClearJob?.cancel()
                        typingClearJob = scope.launch {
                            delay(3_000)
                            typingUserId = null
                        }
                    }
                }
            }
        }
    }

    var messages by mutableStateOf<List<ChatMessage>>(emptyList())
        private set

    var draft by mutableStateOf("")
        private set

    var isSending by mutableStateOf(false)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    var typingUserId by mutableStateOf<String?>(null)
        private set

    var attachmentFiles by mutableStateOf<Map<String, String>>(emptyMap())
        private set

    fun updateDraft(text: String) {
        draft = text
        typingSendJob?.cancel()
        if (text.isNotBlank()) {
            typingSendJob = scope.launch {
                delay(300)
                repository.sendTyping(conversationId)
            }
        }
    }

    fun load() {
        scope.launch {
            try {
                messages = repository.getMessages(conversationId)
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            }
        }
    }

    fun sendText() {
        val text = draft.trim()
        if (text.isEmpty()) return
        draft = ""
        isSending = true
        scope.launch {
            try {
                val msg = repository.sendMessage(conversationId, "text", text)
                appendMessage(msg)
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            } finally {
                isSending = false
            }
        }
    }

    fun sendProposal(kind: String, body: String, detail: String?) {
        isSending = true
        scope.launch {
            try {
                val msg = repository.sendMessage(conversationId, kind, body, detail)
                appendMessage(msg)
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            } finally {
                isSending = false
            }
        }
    }

    fun uploadAttachment(
        kind: String,
        bytes: ByteArray,
        fileName: String,
        contentType: String,
        durationSeconds: Double? = null
    ) {
        if (bytes.isEmpty()) return
        isSending = true
        scope.launch {
            try {
                val message = repository.uploadAttachment(
                    conversationId,
                    kind,
                    bytes,
                    fileName,
                    contentType,
                    durationSeconds
                )
                appendMessage(message)
                message.contentPath?.let { path ->
                    val file = mediaCache.file(path) { bytes }
                    attachmentFiles = attachmentFiles + (path to file.absolutePath)
                }
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            } finally {
                isSending = false
            }
        }
    }

    fun loadAttachment(message: ChatMessage) {
        val path = message.contentPath ?: return
        if (attachmentFiles.containsKey(path)) return
        scope.launch {
            try {
                val file = mediaCache.file(path) {
                    repository.getContentBytes(path)
                }
                attachmentFiles = attachmentFiles + (path to file.absolutePath)
            } catch (error: Exception) {
                error.throwIfCancellation()
                errorMessage = error.message ?: "Не удалось загрузить вложение"
            }
        }
    }

    fun vote(message: ChatMessage) {
        if (message.isVoted) return
        scope.launch {
            try {
                val updated = repository.voteMessage(conversationId, message.id)
                appendMessage(updated)
            } catch (e: Exception) {
                e.throwIfCancellation()
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

    fun reportError(error: Throwable, fallback: String) {
        errorMessage = error.message ?: fallback
    }

    override fun close() {
        scope.cancel()
        repository.closeLiveEvents(conversationId)
    }
}
