package frezzy.gonow.features.activity

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import frezzy.gonow.core.viewModelFactory
import frezzy.gonow.core.MediaCache
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.models.ActivityApplication
import frezzy.gonow.models.ActivityApplicationAnswer
import frezzy.gonow.models.ActivityQuestion
import frezzy.gonow.models.GoNowActivity
import frezzy.gonow.models.UpdateActivityRequest
import frezzy.gonow.ui.theme.Background
import frezzy.gonow.ui.theme.GlassCard
import java.time.Instant
import java.io.File
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.graphics.Color

data class ActivityDetailUiState(
    val activity: GoNowActivity? = null,
    val applications: List<ActivityApplication> = emptyList(),
    val loading: Boolean = true,
    val actionInProgress: Boolean = false,
    val error: String? = null,
    val message: String? = null
)

class ActivityDetailViewModel(
    private val repository: ActivityRepository,
    private val activityId: String
) : ViewModel() {
    var state by mutableStateOf(ActivityDetailUiState())
        private set

    fun load() {
        viewModelScope.launch {
            state = state.copy(loading = true, error = null)
            cancellableRunCatching { repository.getActivity(activityId) }
                .onSuccess { activity ->
                    state = state.copy(activity = activity, loading = false)
                    if (activity.isOrganizer) loadApplications()
                }
                .onFailure { state = state.copy(loading = false, error = it.message ?: "Не удалось загрузить активность") }
        }
    }

    fun apply(message: String?, answers: List<ActivityApplicationAnswer>) = action {
        repository.applyToActivity(activityId, message?.trim()?.ifBlank { null }, answers)
        repository.getActivity(activityId)
    }

    fun setRecruitmentClosed(closed: Boolean) = action {
        repository.updateActivity(activityId, UpdateActivityRequest(recruitmentClosed = closed))
    }

    fun setStatus(status: String) = action {
        repository.updateActivity(activityId, UpdateActivityRequest(status = status))
    }

    fun duplicate() = action("Создан черновик-копия") {
        repository.duplicateActivity(activityId)
    }

    fun decideApplication(applicationId: String, status: String) {
        viewModelScope.launch {
            state = state.copy(actionInProgress = true, error = null)
            cancellableRunCatching { repository.updateApplication(activityId, applicationId, status) }
                .onSuccess { updated ->
                    state = state.copy(
                        applications = state.applications.map { if (it.id == updated.id) updated else it },
                        actionInProgress = false
                    )
                }
                .onFailure { state = state.copy(actionInProgress = false, error = it.message) }
        }
    }

    fun clearMessage() { state = state.copy(message = null) }

    private fun loadApplications() {
        viewModelScope.launch {
            cancellableRunCatching { repository.getApplications(activityId) }
                .onSuccess { state = state.copy(applications = it) }
                .onFailure { state = state.copy(error = it.message) }
        }
    }

    private fun action(successMessage: String? = null, block: suspend () -> GoNowActivity) {
        viewModelScope.launch {
            state = state.copy(actionInProgress = true, error = null, message = null)
            cancellableRunCatching { block() }
                .onSuccess { activity ->
                    state = state.copy(activity = activity, actionInProgress = false, message = successMessage)
                    if (activity.isOrganizer) loadApplications()
                }
                .onFailure { state = state.copy(actionInProgress = false, error = it.message ?: "Не удалось выполнить действие") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    repository: ActivityRepository,
    mediaCache: MediaCache,
    activityId: String,
    initialTitle: String,
    onOpenChat: (conversationId: String, title: String) -> Unit,
    onDismiss: () -> Unit
) {
    val detailViewModel: ActivityDetailViewModel = viewModel(
        key = "activity-detail-$activityId",
        factory = viewModelFactory { ActivityDetailViewModel(repository, activityId) }
    )
    val state = detailViewModel.state
    var showApply by remember { mutableStateOf(false) }
    val photoFiles = remember(activityId) { mutableStateMapOf<String, String>() }
    var photoError by remember(activityId) { mutableStateOf<String?>(null) }
    var photoReload by remember(activityId) { mutableStateOf(0) }

    LaunchedEffect(activityId) { detailViewModel.load() }
    LaunchedEffect(state.activity?.photos, photoReload) {
        state.activity?.photos?.forEach { photo ->
            if (photoFiles.containsKey(photo.id)) return@forEach
            cancellableRunCatching {
                mediaCache.file(photo.contentPath) { repository.getPhotoContent(photo.contentPath) }
            }.onSuccess { photoFiles[photo.id] = it.absolutePath }
                .onFailure { photoError = it.message ?: "Не удалось загрузить фотографии" }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 360.dp, max = 760.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(state.activity?.title ?: initialTitle, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = "Закрыть") }
            }

            when {
                state.loading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                state.activity == null -> {
                    Text(state.error ?: "Активность не найдена", color = MaterialTheme.colorScheme.error)
                    Button(onClick = detailViewModel::load, modifier = Modifier.fillMaxWidth()) { Text("Повторить") }
                }
                else -> ActivityDetailContent(
                    activity = state.activity,
                    photoFiles = photoFiles,
                    applications = state.applications,
                    busy = state.actionInProgress,
                    error = state.error,
                    message = state.message,
                    onApply = { showApply = true },
                    onOpenChat = { id -> onOpenChat(id, state.activity.title) },
                    onRecruitment = detailViewModel::setRecruitmentClosed,
                    onStatus = detailViewModel::setStatus,
                    onDuplicate = detailViewModel::duplicate,
                    onDecision = detailViewModel::decideApplication
                )
            }
            photoError?.let {
                Text(it, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = { photoError = null; photoReload++ }) { Text("Повторить загрузку фото") }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    state.activity?.let { activity ->
        if (showApply) {
            ActivityApplicationDialog(
                questions = activity.additionalQuestions,
                onDismiss = { showApply = false },
                onSubmit = { message, answers ->
                    showApply = false
                    detailViewModel.apply(message, answers)
                }
            )
        }
    }
}

@Composable
private fun ActivityDetailContent(
    activity: GoNowActivity,
    photoFiles: Map<String, String>,
    applications: List<ActivityApplication>,
    busy: Boolean,
    error: String?,
    message: String?,
    onApply: () -> Unit,
    onOpenChat: (String) -> Unit,
    onRecruitment: (Boolean) -> Unit,
    onStatus: (String) -> Unit,
    onDuplicate: () -> Unit,
    onDecision: (String, String) -> Unit
) {
    if (activity.photos.isNotEmpty()) {
        ActivityPhotoGallery(
            files = activity.photos.sortedBy { it.sortIndex }.mapNotNull { photoFiles[it.id] }
        )
    }
    if (activity.description.isNotBlank()) Text(activity.description)

    GlassCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            activity.startsAt?.let { DetailRow(Icons.Default.CalendarToday, "Когда", formatDate(it)) }
            val location = activity.location
            val place = listOfNotNull(location?.venueName, location?.address).joinToString(", ")
            if (place.isNotBlank()) DetailRow(Icons.Default.LocationOn, "Где", place)
            DetailRow(
                Icons.Default.People,
                "Участники",
                activity.participantLimit?.let { "${activity.participantCount} из $it" } ?: activity.participantCount.toString()
            )
            if (activity.languages.isNotEmpty()) Text("Языки: ${activity.languages.joinToString()}")
            if (activity.ageMin != null || activity.ageMax != null) {
                Text("Возраст: ${activity.ageMin ?: 0}–${activity.ageMax ?: "без ограничения"}")
            }
            if (activity.costType != "free") {
                Text("Стоимость: ${activity.costAmountCents?.let { "${it / 100.0}" } ?: activity.costType}${activity.costNote?.let { ", $it" }.orEmpty()}")
            }
        }
    }

    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

    if (activity.isOrganizer) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Набор закрыт", modifier = Modifier.weight(1f))
            Switch(checked = activity.recruitmentClosed, onCheckedChange = { onRecruitment(it) }, enabled = !busy)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDuplicate, enabled = !busy, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.ContentCopy, contentDescription = null)
                Text("Повторить")
            }
            if (activity.status !in listOf("completed", "cancelled")) {
                OutlinedButton(onClick = { onStatus("cancelled") }, enabled = !busy, modifier = Modifier.weight(1f)) {
                    Text("Отменить")
                }
            }
        }
        if (applications.isNotEmpty()) {
            Text("Заявки", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            applications.forEach { application ->
                GlassCard {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(application.applicant.displayName, fontWeight = FontWeight.SemiBold)
                        application.message?.let { Text(it) }
                        application.answers.forEach { Text(it.value, style = MaterialTheme.typography.bodySmall) }
                        if (application.status == "pending") {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = { onDecision(application.id, "accepted") }, enabled = !busy) { Text("Принять") }
                                OutlinedButton(onClick = { onDecision(application.id, "rejected") }, enabled = !busy) { Text("Отклонить") }
                            }
                        } else Text(application.parsedStatus.titleRu)
                    }
                }
            }
        }
    } else {
        when {
            activity.canAccessChat && activity.chatConversationId != null -> {
                Button(onClick = { onOpenChat(activity.chatConversationId) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = null)
                    Text("Открыть чат")
                }
            }
            activity.applicationStatus == "pending" -> OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) { Text("Заявка отправлена") }
            activity.isFull || activity.recruitmentClosed -> OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) { Text("Набор закрыт") }
            else -> Button(onClick = onApply, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Присоединиться") }
        }
    }
}

@Composable
private fun ActivityPhotoGallery(files: List<String>) {
    var selected by remember { mutableStateOf<String?>(null) }
    if (files.isEmpty()) {
        Box(modifier = Modifier.fillMaxWidth().height(180.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
    } else {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(files) { path ->
                val file = remember(path) { File(path) }
                val bitmap = remember(path) { BitmapFactory.decodeFile(file.absolutePath) }
                bitmap?.let {
                    Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = "Фотография активности",
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(width = 260.dp, height = 180.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .clickable { selected = path }
                    )
                }
            }
        }
    }
    selected?.let { path ->
        Dialog(onDismissRequest = { selected = null }) {
            val bitmap = remember(path) { BitmapFactory.decodeFile(path) }
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black).clickable { selected = null },
                contentAlignment = Alignment.Center
            ) {
                bitmap?.let {
                    Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = "Фотография активности на весь экран",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }
}

@Composable
private fun ActivityApplicationDialog(
    questions: List<ActivityQuestion>,
    onDismiss: () -> Unit,
    onSubmit: (String?, List<ActivityApplicationAnswer>) -> Unit
) {
    var message by remember { mutableStateOf("") }
    val answers = remember { mutableStateMapOf<String, String>() }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Заявка на участие") },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = message, onValueChange = { message = it.take(500) }, label = { Text("Сообщение организатору") })
                questions.forEach { question ->
                    OutlinedTextField(
                        value = answers[question.id].orEmpty(),
                        onValueChange = { answers[question.id] = it },
                        label = { Text(question.prompt + if (question.required) " *" else "") }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSubmit(
                        message.ifBlank { null },
                        answers.map { ActivityApplicationAnswer(it.key, it.value) }
                    )
                },
                enabled = questions.filter { it.required }.all { answers[it.id]?.isNotBlank() == true }
            ) { Text("Отправить") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } }
    )
}

@Composable
private fun DetailRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Column { Text(label, style = MaterialTheme.typography.labelSmall); Text(value) }
    }
}

private fun formatDate(value: String): String = runCatching {
    val instant = runCatching { Instant.parse(value) }.getOrElse { OffsetDateTime.parse(value).toInstant() }
    DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm").withZone(ZoneId.systemDefault()).format(instant)
}.getOrDefault(value)
