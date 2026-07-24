package frezzy.gonow.features.social

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.models.Conversation
import frezzy.gonow.models.CreateInvitationRequest
import frezzy.gonow.models.MeetingTemplate
import frezzy.gonow.models.PublicUserProfile
import frezzy.gonow.models.SocialUser
import frezzy.gonow.ui.theme.Background
import frezzy.gonow.ui.theme.GlassCard
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublicUserProfileSheet(
    repository: SocialRepository,
    socialUser: SocialUser,
    onUserChanged: (SocialUser) -> Unit,
    onConversation: (Conversation) -> Unit,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var profile by remember(socialUser.id) { mutableStateOf<PublicUserProfile?>(null) }
    var avatarBytes by remember(socialUser.id) { mutableStateOf<ByteArray?>(null) }
    var loading by remember(socialUser.id) { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var showInvitation by remember { mutableStateOf(false) }

    LaunchedEffect(socialUser.id) {
        loading = true
        cancellableRunCatching {
            repository.getPublicProfile(socialUser.id)
        }.onSuccess { loadedProfile ->
            profile = loadedProfile
        }.onFailure { error = it.message ?: "Не удалось загрузить профиль" }
        socialUser.avatarPath?.let { path ->
            cancellableRunCatching { repository.getContentBytes(path) }
                .onSuccess { avatarBytes = it }
                .onFailure { error = it.message ?: "Не удалось загрузить аватар" }
        }
        loading = false
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
                .heightIn(min = 400.dp, max = 760.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(profile?.displayName ?: socialUser.displayName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = "Закрыть") }
            }

            if (loading) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            } else {
                avatarBytes?.let { bytes ->
                    val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
                    bitmap?.let { decoded ->
                        Image(
                            bitmap = decoded.asImageBitmap(),
                            contentDescription = "Аватар ${profile?.displayName ?: socialUser.displayName}",
                            modifier = Modifier.size(96.dp).clip(CircleShape).align(Alignment.CenterHorizontally),
                            contentScale = ContentScale.Crop
                        )
                    }
                }
                profile?.let { value ->
                    Text("@${value.username}", color = MaterialTheme.colorScheme.primary)
                    val meta = listOfNotNull(value.age?.let { "$it лет" }, value.city, value.occupation)
                    if (meta.isNotEmpty()) Text(meta.joinToString(" · "))
                    value.bio?.takeIf { it.isNotBlank() }?.let { Text(it) }
                    if (value.interests.isNotEmpty()) Text("Интересы: ${value.interests.joinToString()}")
                    if (value.languages.isNotEmpty()) Text("Языки: ${value.languages.joinToString()}")
                    GlassCard {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Рейтинг: ${"%.1f".format(value.rating)}")
                            value.availability?.let { Text("Доступность: $it") }
                            value.preferredGroupSize?.let { Text("Компания: $it") }
                            value.distanceKm?.let { Text("Расстояние: ${"%.1f".format(it)} км") }
                        }
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            if (socialUser.hasPendingRequest && !socialUser.isIncomingRequest) return@OutlinedButton
                            scope.launch {
                                busy = true
                                cancellableRunCatching {
                                    when {
                                        socialUser.isFriend -> repository.removeFriend(socialUser.id)
                                        socialUser.isIncomingRequest -> repository.decideFriend(socialUser.id, "accept")
                                        else -> repository.requestFriend(socialUser.id)
                                    }
                                }.onSuccess(onUserChanged).onFailure { error = it.message }
                                busy = false
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.PersonAdd, contentDescription = null)
                        Text(if (socialUser.isFriend) "Удалить" else if (socialUser.hasPendingRequest) "Ожидает" else "В друзья")
                    }
                    if (socialUser.canMessage) {
                        IconButton(onClick = {
                            scope.launch {
                                cancellableRunCatching { repository.createConversation(socialUser.id) }
                                    .onSuccess(onConversation)
                                    .onFailure { error = it.message }
                            }
                        }) { Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = "Написать") }
                    }
                    if (socialUser.canInvite) {
                        TextButton(onClick = { showInvitation = true }) { Text("Позвать") }
                    }
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (showInvitation) {
        InvitationDialog(
            onDismiss = { showInvitation = false },
            onSubmit = { template, place, message ->
                showInvitation = false
                scope.launch {
                    cancellableRunCatching {
                        repository.createInvitation(
                            CreateInvitationRequest(socialUser.id, template.apiValue, place = place, message = message)
                        )
                    }.onFailure { error = it.message }
                }
            }
        )
    }
}

@Composable
private fun InvitationDialog(
    onDismiss: () -> Unit,
    onSubmit: (MeetingTemplate, String?, String?) -> Unit
) {
    var template by remember { mutableStateOf(MeetingTemplate.WALK) }
    var place by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Предложить встречу") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MeetingTemplate.entries.forEach { value ->
                        FilterChip(selected = template == value, onClick = { template = value }, label = { Text(value.titleRu) })
                    }
                }
                OutlinedTextField(value = place, onValueChange = { place = it }, label = { Text("Место") })
                OutlinedTextField(value = message, onValueChange = { message = it }, label = { Text("Сообщение") })
            }
        },
        confirmButton = { TextButton(onClick = { onSubmit(template, place.ifBlank { null }, message.ifBlank { null }) }) { Text("Отправить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } }
    )
}
