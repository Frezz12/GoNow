package frezzy.gonow.features.chat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.ChatMessage
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.ui.theme.*
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import frezzy.gonow.core.MediaCache
import frezzy.gonow.core.cancellableRunCatching
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationSheet(
    repository: SocialRepository,
    mediaCache: MediaCache,
    conversationId: String,
    title: String,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val viewModel = remember(repository, mediaCache, conversationId) {
        ConversationViewModel(repository, mediaCache, conversationId, title)
    }
    DisposableEffect(viewModel) { onDispose(viewModel::close) }
    val voiceRecorder = remember { VoiceRecorder(context.applicationContext) }
    var isRecording by remember { mutableStateOf(false) }
    var showAttachMenu by remember { mutableStateOf(false) }
    var proposalKind by remember { mutableStateOf<String?>(null) }

    fun uploadUri(uri: Uri, forcedKind: String? = null) {
        scope.launch {
            cancellableRunCatching { preparePickedFile(context, uri, forcedKind) }
                .onSuccess { picked ->
                    val kind = forcedKind ?: when {
                        picked.contentType.startsWith("image/") -> "image"
                        picked.contentType.startsWith("video/") -> "video"
                        picked.contentType.startsWith("audio/") -> "audio"
                        else -> "file"
                    }
                    viewModel.uploadAttachment(kind, picked.bytes, picked.name, picked.contentType)
                }
                .onFailure { viewModel.reportError(it, "Не удалось прочитать вложение") }
        }
    }

    val visualPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let(::uploadUri)
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { uploadUri(it, "file") }
    }
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) runCatching { voiceRecorder.start() }
            .onSuccess { isRecording = true }
            .onFailure { viewModel.reportError(it, "Не удалось начать запись") }
    }

    fun toggleVoiceRecording() {
        if (isRecording) {
            runCatching { voiceRecorder.stop() }
                .onSuccess { recording ->
                    recording?.let {
                        val bytes = it.file.readBytes()
                        viewModel.uploadAttachment("voice", bytes, it.file.name, "audio/mp4", it.durationSeconds)
                        it.file.delete()
                    }
                }
                .onFailure { viewModel.reportError(it, "Не удалось завершить запись") }
            isRecording = false
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            runCatching { voiceRecorder.start() }
                .onSuccess { isRecording = true }
                .onFailure { viewModel.reportError(it, "Не удалось начать запись") }
        } else {
            microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    LaunchedEffect(conversationId) { viewModel.load() }
    DisposableEffect(Unit) { onDispose { voiceRecorder.cancel() } }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth().heightIn(min = 400.dp, max = 600.dp)) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Закрыть")
                }
                Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
            }

            // Messages
            LazyColumn(
                modifier = Modifier.weight(1f).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (viewModel.messages.isEmpty()) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Filled.ChatBubbleOutline, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(40.dp))
                                Spacer(modifier = Modifier.height(8.dp))
                                Text("Начните разговор", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                items(viewModel.messages, key = { it.id }) { msg ->
                    ChatMessageBubble(
                        message = msg,
                        attachmentFile = msg.contentPath?.let(viewModel.attachmentFiles::get)?.let(::File),
                        onLoadAttachment = { viewModel.loadAttachment(msg) },
                        onVote = { viewModel.vote(msg) }
                    )
                }
            }

            if (viewModel.typingUserId != null) {
                Text(
                    "Печатает…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 2.dp)
                )
            }

            // Composer
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box {
                    IconButton(onClick = { showAttachMenu = true }) {
                        Icon(Icons.Default.Add, contentDescription = "Добавить вложение")
                    }
                    DropdownMenu(expanded = showAttachMenu, onDismissRequest = { showAttachMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("Фото или видео") },
                            onClick = {
                                showAttachMenu = false
                                visualPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                            }
                        )
                        DropdownMenuItem(text = { Text("Файл") }, onClick = { showAttachMenu = false; filePicker.launch("*/*") })
                        DropdownMenuItem(text = { Text(if (isRecording) "Остановить запись" else "Голосовое") }, onClick = { showAttachMenu = false; toggleVoiceRecording() })
                        DropdownMenuItem(text = { Text("Предложить место") }, onClick = { showAttachMenu = false; proposalKind = "placeProposal" })
                        DropdownMenuItem(text = { Text("Предложить время") }, onClick = { showAttachMenu = false; proposalKind = "timeProposal" })
                    }
                }
                OutlinedTextField(
                    value = viewModel.draft,
                    onValueChange = viewModel::updateDraft,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(22.dp),
                    placeholder = { Text("Сообщение") },
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
                    singleLine = false,
                    maxLines = 3
                )
                FilledIconButton(
                    onClick = { viewModel.sendText() },
                    enabled = viewModel.draft.isNotBlank() && !viewModel.isSending,
                    modifier = Modifier.size(44.dp),
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary
                    )
                ) {
                    if (viewModel.isSending) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    } else {
                        Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Отправить")
                    }
                }
            }

            if (isRecording) {
                Text("Идёт запись… нажмите +, чтобы остановить", color = MaterialTheme.colorScheme.error, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp))
            }

            viewModel.errorMessage?.let { err ->
                Text(err, color = Danger, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            }
        }
    }

    proposalKind?.let { kind ->
        ProposalDialog(
            kind = kind,
            onDismiss = { proposalKind = null },
            onSubmit = { body, detail ->
                proposalKind = null
                viewModel.sendProposal(kind, body, detail)
            }
        )
    }
}

@Composable
private fun ChatMessageBubble(
    message: ChatMessage,
    attachmentFile: File?,
    onLoadAttachment: () -> Unit,
    onVote: () -> Unit
) {
    val isMine = message.isMine

    when {
        message.kind == "system" -> {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    text = message.body,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }
        }
        message.isAttachment -> AttachmentBubble(message, attachmentFile, onLoadAttachment)
        message.isProposal -> {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = if (isMine) Alignment.End else Alignment.Start
            ) {
                Card(
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (isMine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface
                    ),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(
                                if (message.kind == "placeProposal") Icons.Filled.LocationOn else Icons.Filled.AccessTime,
                                contentDescription = null,
                                tint = if (isMine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(14.dp)
                            )
                            Text(
                                if (message.kind == "placeProposal") "Предложение места" else "Предложение времени",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (isMine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary
                            )
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(message.body, fontSize = 14.sp, color = if (isMine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
                        message.proposalDetail?.let {
                            if (it.isNotBlank()) {
                                Text(it, fontSize = 12.sp, color = if (isMine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.7f) else MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        HorizontalDivider(color = if (isMine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.3f) else MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(
                            onClick = onVote,
                            enabled = !message.isVoted,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                if (message.isVoted) "Вы выбрали · ${message.voteCount}" else "Подходит · ${message.voteCount}",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (message.isVoted) Success else if (isMine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        }
        else -> {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = if (isMine) Alignment.End else Alignment.Start
            ) {
                if (!isMine && message.senderName.isNotBlank()) {
                    Text(message.senderName, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 4.dp, bottom = 2.dp))
                }
                Box(
                    modifier = Modifier.widthIn(max = 280.dp)
                        .clip(RoundedCornerShape(topStart = if (isMine) 18.dp else 4.dp, topEnd = if (isMine) 4.dp else 18.dp, bottomStart = 18.dp, bottomEnd = 18.dp))
                        .background(if (isMine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant)
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                ) {
                    Text(
                        text = message.body,
                        fontSize = 14.sp,
                        color = if (isMine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
    }
}

@Composable
private fun AttachmentBubble(message: ChatMessage, file: File?, onLoad: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(message.contentPath) { if (file == null) onLoad() }
    GlassCard(modifier = Modifier.widthIn(max = 300.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(message.attachmentName ?: message.kind, fontWeight = FontWeight.SemiBold)
            when {
                file == null -> CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                message.kind == "image" -> {
                    val bitmap = remember(file) { BitmapFactory.decodeFile(file.absolutePath) }
                    bitmap?.let {
                        Image(
                            bitmap = it.asImageBitmap(),
                            contentDescription = message.attachmentName,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(12.dp))
                        )
                    }
                }
                message.kind in listOf("video", "audio", "voice") -> MediaAttachmentPlayer(file, message.kind)
                else -> {
                    Text("${message.attachmentContentType.orEmpty()} · ${message.attachmentBytes ?: file.length()} байт")
                    TextButton(onClick = {
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, message.attachmentContentType ?: "application/octet-stream")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        runCatching { context.startActivity(intent) }
                    }) { Text("Открыть") }
                }
            }
        }
    }
}

@Composable
private fun MediaAttachmentPlayer(file: File, kind: String) {
    val context = LocalContext.current
    val player = remember(file) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
            prepare()
        }
    }
    DisposableEffect(player) {
        onDispose { player.release() }
    }
    AndroidView(
        factory = { PlayerView(it).apply { this.player = player; useController = true } },
        modifier = Modifier.fillMaxWidth().height(if (kind == "video") 190.dp else 72.dp)
    )
}

@Composable
private fun ProposalDialog(kind: String, onDismiss: () -> Unit, onSubmit: (String, String?) -> Unit) {
    var body by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (kind == "placeProposal") "Предложить место" else "Предложить время") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = body, onValueChange = { body = it }, label = { Text("Предложение") })
                OutlinedTextField(value = detail, onValueChange = { detail = it }, label = { Text("Комментарий") })
            }
        },
        confirmButton = { TextButton(onClick = { onSubmit(body.trim(), detail.trim().ifBlank { null }) }, enabled = body.isNotBlank()) { Text("Отправить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } }
    )
}

private data class PickedFile(val bytes: ByteArray, val name: String, val contentType: String)

private suspend fun preparePickedFile(context: Context, uri: Uri, forcedKind: String?): PickedFile {
    val contentType = context.contentResolver.getType(uri) ?: "application/octet-stream"
    if (forcedKind == null && contentType.startsWith("image/")) {
        return optimizePickedImage(context, uri)
    }
    if (forcedKind == null && contentType.startsWith("video/")) {
        val transformed = cancellableRunCatching { transcodePickedVideo(context, uri) }.getOrNull()
        if (transformed != null) {
            return try {
                val bytes = withContext(Dispatchers.IO) { transformed.readBytes() }
                require(bytes.size <= 50 * 1024 * 1024) { "Видео больше 50 МБ после обработки" }
                PickedFile(bytes, "video-${System.currentTimeMillis()}.mp4", "video/mp4")
            } finally {
                transformed.delete()
            }
        }
    }
    return readPickedFile(context, uri)
}

private suspend fun optimizePickedImage(context: Context, uri: Uri): PickedFile = withContext(Dispatchers.IO) {
    val source = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        ?: error("Не удалось прочитать изображение")
    val largest = maxOf(source.width, source.height)
    val scale = if (largest > 1_280) 1_280f / largest else 1f
    val bitmap = if (scale < 1f) {
        Bitmap.createScaledBitmap(source, (source.width * scale).toInt(), (source.height * scale).toInt(), true)
    } else source
    val bytes = ByteArrayOutputStream().use { output ->
        check(bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output))
        output.toByteArray()
    }
    PickedFile(bytes, "image-${System.currentTimeMillis()}.jpg", "image/jpeg")
}

@androidx.annotation.OptIn(UnstableApi::class)
private suspend fun transcodePickedVideo(context: Context, uri: Uri): File =
    suspendCancellableCoroutine { continuation ->
        val output = File.createTempFile("gonow-video-", ".mp4", context.cacheDir).also { it.delete() }
        lateinit var transformer: Transformer
        val listener = object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                if (continuation.isActive) continuation.resume(output)
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException
            ) {
                output.delete()
                if (continuation.isActive) continuation.resumeWithException(exportException)
            }
        }
        transformer = Transformer.Builder(context.applicationContext)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(listener)
            .build()
        continuation.invokeOnCancellation {
            transformer.cancel()
            output.delete()
        }
        try {
            transformer.start(MediaItem.fromUri(uri), output.absolutePath)
        } catch (error: Exception) {
            output.delete()
            if (continuation.isActive) continuation.resumeWithException(error)
        }
    }

private suspend fun readPickedFile(context: Context, uri: Uri): PickedFile = withContext(Dispatchers.IO) {
    val type = context.contentResolver.getType(uri) ?: "application/octet-stream"
    var declaredSize: Long? = null
    val name = context.contentResolver.query(
        uri,
        arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
        null,
        null,
        null
    )?.use { cursor ->
        if (!cursor.moveToFirst()) return@use null
        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) declaredSize = cursor.getLong(sizeIndex)
        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (nameIndex >= 0) cursor.getString(nameIndex) else null
    } ?: "attachment"
    require(declaredSize == null || declaredSize!! <= 50L * 1024 * 1024) { "Файл больше 50 МБ" }
    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        ?: error("Не удалось прочитать выбранный файл")
    require(bytes.size <= 50 * 1024 * 1024) { "Файл больше 50 МБ" }
    PickedFile(bytes, name, type)
}
