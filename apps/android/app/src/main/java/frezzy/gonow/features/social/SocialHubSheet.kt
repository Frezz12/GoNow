package frezzy.gonow.features.social

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.core.throwIfCancellation
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.models.Conversation
import frezzy.gonow.models.CreateInvitationRequest
import frezzy.gonow.models.MeetingInvitation
import frezzy.gonow.models.MeetingTemplate
import frezzy.gonow.models.SocialUser
import frezzy.gonow.ui.theme.AuthBackdrop
import frezzy.gonow.ui.theme.GlassCard
import frezzy.gonow.ui.theme.GlassSecondaryButton
import frezzy.gonow.ui.theme.GradientPrimaryButton
import frezzy.gonow.ui.theme.Success
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class SocialSection(val titleRu: String) {
    FRIENDS("Друзья"), PEOPLE("Люди"), INVITATIONS("Встречи")
}

/** A full-screen social destination, deliberately independent from the chat tab. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SocialHubSheet(
    repository: SocialRepository,
    initialSection: SocialSection = SocialSection.FRIENDS,
    initialUserId: String? = null,
    onConversation: (Conversation) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            AuthBackdrop {
                SocialHubContent(repository, initialSection, initialUserId, onConversation, onDismiss)
            }
        }
    }
}

@Composable
private fun SocialHubContent(
    repository: SocialRepository,
    initialSection: SocialSection,
    initialUserId: String?,
    onConversation: (Conversation) -> Unit,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val horizontalPadding = if (LocalConfiguration.current.screenWidthDp >= 600) 32.dp else 16.dp
    var section by remember(initialSection) { mutableStateOf(initialSection) }
    var people by remember { mutableStateOf<List<SocialUser>>(emptyList()) }
    var invitations by remember { mutableStateOf<List<MeetingInvitation>>(emptyList()) }
    var query by rememberSaveable { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var selectedUser by remember { mutableStateOf<SocialUser?>(null) }
    var invitee by remember { mutableStateOf<SocialUser?>(null) }

    fun replaceUser(updated: SocialUser) {
        people = people.map { if (it.id == updated.id) updated else it }
        if (selectedUser?.id == updated.id) selectedUser = updated
    }

    fun loadAll() {
        scope.launch {
            isLoading = true
            errorMessage = null
            cancellableRunCatching {
                repository.getPeople() to repository.getInvitations()
            }.onSuccess { (loadedPeople, loadedInvitations) ->
                people = loadedPeople
                invitations = loadedInvitations
                if (initialUserId != null && selectedUser == null) {
                    selectedUser = people.firstOrNull { it.id == initialUserId }
                    if (selectedUser == null) {
                        val profile = repository.getPublicProfile(initialUserId)
                        selectedUser = SocialUser(
                            id = profile.id,
                            displayName = profile.displayName,
                            username = profile.username,
                            city = profile.city,
                            bio = profile.bio,
                            interests = profile.interests
                        )
                    }
                }
            }.onFailure {
                it.throwIfCancellation()
                errorMessage = it.message ?: "Не удалось загрузить друзей и приглашения"
            }
            isLoading = false
        }
    }

    fun friendAction(user: SocialUser) {
        if (user.hasPendingRequest && !user.isIncomingRequest) return
        scope.launch {
            cancellableRunCatching {
                when {
                    user.isFriend -> repository.removeFriend(user.id)
                    user.isIncomingRequest -> repository.decideFriend(user.id, "accept")
                    else -> repository.requestFriend(user.id)
                }
            }.onSuccess(::replaceUser).onFailure { errorMessage = it.message }
        }
    }

    fun openConversation(user: SocialUser) {
        scope.launch {
            cancellableRunCatching { repository.createConversation(user.id) }
                .onSuccess(onConversation)
                .onFailure { errorMessage = it.message }
        }
    }

    LaunchedEffect(Unit) { loadAll() }
    LaunchedEffect(query) {
        if (section != SocialSection.PEOPLE || query.isBlank()) return@LaunchedEffect
        delay(300)
        cancellableRunCatching { repository.getPeople(query.trim()) }
            .onSuccess { people = it }
            .onFailure { errorMessage = it.message }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = horizontalPadding, vertical = 12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FilledTonalIconButton(onClick = onDismiss, modifier = Modifier.size(48.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Назад")
            }
            Text(
                text = "Друзья и встречи",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            Spacer(Modifier.size(48.dp))
        }

        Spacer(Modifier.height(24.dp))
        SocialSectionPicker(section = section, onSelected = { section = it })
        Spacer(Modifier.height(16.dp))

        if (section == SocialSection.PEOPLE) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Имя, @username или город") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
                shape = RoundedCornerShape(18.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.82f),
                    focusedContainerColor = MaterialTheme.colorScheme.surface
                )
            )
            Spacer(Modifier.height(12.dp))
        }

        Box(Modifier.weight(1f)) {
            when {
                isLoading -> LoadingState()
                errorMessage != null && people.isEmpty() && invitations.isEmpty() -> RetryState(errorMessage.orEmpty(), ::loadAll)
                section == SocialSection.INVITATIONS -> InvitationList(
                    invitations = invitations,
                    onDecision = { invitation, action ->
                        scope.launch {
                            cancellableRunCatching { repository.decideInvitation(invitation.id, action) }
                                .onSuccess { updated -> invitations = invitations.map { if (it.id == updated.id) updated else it } }
                                .onFailure { errorMessage = it.message }
                        }
                    },
                    onOpenChat = { invitation ->
                        val conversationId = invitation.conversationId ?: return@InvitationList
                        scope.launch {
                            cancellableRunCatching { repository.getConversations().firstOrNull { it.id == conversationId } }
                                .onSuccess { conversation ->
                                    if (conversation != null) onConversation(conversation)
                                    else errorMessage = "Чат для встречи пока недоступен"
                                }
                                .onFailure { errorMessage = it.message }
                        }
                    }
                )
                else -> {
                    val users = when (section) {
                        SocialSection.FRIENDS -> people.filter(SocialUser::isFriend)
                        SocialSection.PEOPLE -> people
                        SocialSection.INVITATIONS -> emptyList()
                    }
                    if (users.isEmpty()) {
                        EmptyState(if (section == SocialSection.FRIENDS) "Пока нет друзей" else "Никого не найдено")
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(bottom = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            items(users, key = SocialUser::id) { user ->
                                SocialUserCard(
                                    user = user,
                                    onOpen = { selectedUser = user },
                                    onFriend = { friendAction(user) },
                                    onMessage = { openConversation(user) },
                                    onInvite = { invitee = user }
                                )
                            }
                        }
                    }
                }
            }
        }

        errorMessage?.let { message ->
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }

    selectedUser?.let { user ->
        PublicUserProfileSheet(
            repository = repository,
            socialUser = user,
            onUserChanged = ::replaceUser,
            onConversation = onConversation,
            onDismiss = { selectedUser = null }
        )
    }
    invitee?.let { user ->
        InviteMeetingSheet(
            repository = repository,
            user = user,
            onCreated = { created ->
                invitations = listOf(created) + invitations.filterNot { it.id == created.id }
                invitee = null
            },
            onDismiss = { invitee = null }
        )
    }
}

@Composable
private fun SocialSectionPicker(section: SocialSection, onSelected: (SocialSection) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().height(52.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.88f),
        shape = RoundedCornerShape(18.dp)
    ) {
        Row(Modifier.padding(4.dp)) {
            SocialSection.entries.forEach { item ->
                val selected = item == section
                Surface(
                    onClick = { onSelected(item) },
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    shape = RoundedCornerShape(14.dp),
                    color = if (selected) MaterialTheme.colorScheme.surface else Color.Transparent,
                    shadowElevation = if (selected) 1.dp else 0.dp
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(item.titleRu, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium)
                    }
                }
            }
        }
    }
}

@Composable
private fun SocialUserCard(
    user: SocialUser,
    onOpen: () -> Unit,
    onFriend: () -> Unit,
    onMessage: () -> Unit,
    onInvite: () -> Unit
) {
    var aboutExpanded by rememberSaveable(user.id) { mutableStateOf(false) }
    GlassCard(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier.size(56.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center
            ) {
                Text(user.initials, color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold, fontSize = 20.sp)
            }
            Column(Modifier.weight(1f)) {
                Text(user.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                user.username.takeIf(String::isNotBlank)?.let { Text("@$it", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium) }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Открыть профиль", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        if (user.city != null || user.bio != null || user.interests.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth().clickable { aboutExpanded = !aboutExpanded }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Info, contentDescription = null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(10.dp))
                Text("О человеке", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Icon(
                    if (aboutExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = if (aboutExpanded) "Скрыть информацию" else "Показать информацию"
                )
            }
            if (aboutExpanded) {
                user.city?.let { InfoLine(Icons.Filled.LocationOn, it) }
                user.bio?.takeIf(String::isNotBlank)?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp)) }
                if (user.interests.isNotEmpty()) Text(user.interests.joinToString(" · "), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
            }
        }

        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(
                onClick = onFriend,
                enabled = !(user.hasPendingRequest && !user.isIncomingRequest),
                modifier = Modifier.height(48.dp).weight(1f),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = if (user.isFriend) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
            ) {
                Icon(if (user.isFriend) Icons.Filled.PersonRemove else Icons.Filled.PersonAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(when {
                    user.isFriend -> "Удалить"
                    user.isIncomingRequest -> "Принять"
                    user.hasPendingRequest -> "Отправлено"
                    else -> "В друзья"
                })
            }
            if (user.canMessage) {
                FilledTonalIconButton(onClick = onMessage, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = "Написать")
                }
            }
            if (user.canInvite) {
                FilledTonalIconButton(onClick = onInvite, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Filled.DirectionsWalk, contentDescription = "Пригласить на встречу")
                }
            }
        }
    }
}

@Composable
private fun InvitationList(
    invitations: List<MeetingInvitation>,
    onDecision: (MeetingInvitation, String) -> Unit,
    onOpenChat: (MeetingInvitation) -> Unit
) {
    if (invitations.isEmpty()) {
        EmptyState("Нет приглашений на встречи")
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(invitations, key = MeetingInvitation::id) { invitation ->
                InvitationCard(invitation, onDecision, onOpenChat)
            }
        }
    }
}

@Composable
private fun InvitationCard(
    invitation: MeetingInvitation,
    onDecision: (MeetingInvitation, String) -> Unit,
    onOpenChat: (MeetingInvitation) -> Unit
) {
    GlassCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                modifier = Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center
            ) {
                Icon(MeetingTemplate.fromApi(invitation.template).icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            Column(Modifier.weight(1f)) {
                Text(invitation.templateTitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(if (invitation.isIncoming) "От ${invitation.senderName}" else "Для ${invitation.recipientName}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
            Text(invitation.statusTitle, color = if (invitation.status == "accepted") Success else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge)
        }
        invitation.proposedAt?.let { raw -> formatInvitationDate(raw)?.let { InfoLine(Icons.Filled.CalendarToday, it) } }
        invitation.place?.takeIf(String::isNotBlank)?.let { InfoLine(Icons.Filled.LocationOn, it) }
        invitation.message?.takeIf(String::isNotBlank)?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp)) }
        if (invitation.isIncoming && invitation.status == "pending") {
            Spacer(Modifier.height(14.dp))
            GradientPrimaryButton(text = "Принять", onClick = { onDecision(invitation, "accept") })
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = { onDecision(invitation, "counter") }) { Text("Другое время / место") }
                TextButton(onClick = { onDecision(invitation, "decline") }) { Text("Отклонить", color = MaterialTheme.colorScheme.error) }
            }
        }
        if (invitation.conversationId != null) {
            Spacer(Modifier.height(8.dp))
            GlassSecondaryButton(text = "Открыть чат", onClick = { onOpenChat(invitation) })
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun InviteMeetingSheet(
    repository: SocialRepository,
    user: SocialUser,
    onCreated: (MeetingInvitation) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var template by remember { mutableStateOf(MeetingTemplate.WALK) }
    var hasDate by remember { mutableStateOf(true) }
    var proposedAt by remember { mutableStateOf(Instant.now().plusSeconds(7_200)) }
    var place by rememberSaveable { mutableStateOf("") }
    var message by rememberSaveable { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("Пригласить ${user.displayName}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("Чем хотите заняться?", style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MeetingTemplate.entries.forEach { item ->
                    FilterChip(selected = template == item, onClick = { template = item }, label = { Text(item.titleRu) }, leadingIcon = if (template == item) {{ Icon(item.icon, contentDescription = null, modifier = Modifier.size(18.dp)) }} else null)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Предложить дату и время", modifier = Modifier.weight(1f))
                Switch(checked = hasDate, onCheckedChange = { hasDate = it })
            }
            if (hasDate) {
                OutlinedButton(
                    onClick = {
                        val calendar = Calendar.getInstance().apply { timeInMillis = proposedAt.toEpochMilli() }
                        DatePickerDialog(context, { _, year, month, day ->
                            calendar.set(year, month, day)
                            TimePickerDialog(context, { _, hour, minute ->
                                calendar.set(Calendar.HOUR_OF_DAY, hour)
                                calendar.set(Calendar.MINUTE, minute)
                                proposedAt = Instant.ofEpochMilli(calendar.timeInMillis)
                            }, calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE), true).show()
                        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH)).show()
                    },
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(formatInvitationDate(proposedAt.toString()) ?: "Выбрать дату")
                }
            }
            OutlinedTextField(value = place, onValueChange = { place = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Где") }, placeholder = { Text("Можно решить позже") }, singleLine = true)
            OutlinedTextField(value = message, onValueChange = { message = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Сообщение") }, minLines = 3, maxLines = 4)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            GradientPrimaryButton(
                text = "Пригласить ${user.displayName}",
                loading = sending,
                onClick = {
                    scope.launch {
                        sending = true
                        cancellableRunCatching {
                            repository.createInvitation(CreateInvitationRequest(
                                recipientId = user.id,
                                template = template.apiValue,
                                proposedAt = if (hasDate) proposedAt.toString() else null,
                                place = place.trim().ifBlank { null },
                                message = message.trim().ifBlank { null }
                            ))
                        }.onSuccess(onCreated).onFailure { error = it.message ?: "Не удалось отправить приглашение" }
                        sending = false
                    }
                }
            )
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun InfoLine(icon: ImageVector, text: String) {
    Row(modifier = Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
    }
}

private val MeetingTemplate.icon: ImageVector
    get() = when (this) {
        MeetingTemplate.WALK -> Icons.Filled.DirectionsWalk
        MeetingTemplate.COFFEE -> Icons.Filled.Coffee
        MeetingTemplate.CINEMA -> Icons.Filled.Movie
        MeetingTemplate.DINNER -> Icons.Filled.Restaurant
        MeetingTemplate.BICYCLE -> Icons.Filled.DirectionsBike
        MeetingTemplate.GAMES -> Icons.Filled.Gamepad
        MeetingTemplate.CONCERT -> Icons.Filled.MusicNote
        MeetingTemplate.TALK -> Icons.Filled.Forum
    }

private val MeetingInvitation.statusTitle: String
    get() = when (status) {
        "pending" -> "Ожидает"
        "accepted" -> "Принято"
        "declined" -> "Отклонено"
        "expired" -> "Истекло"
        "countered" -> "Нужны изменения"
        else -> status
    }

private fun formatInvitationDate(value: String): String? = runCatching {
    DateTimeFormatter.ofPattern("d MMMM yyyy, HH:mm", Locale("ru"))
        .withZone(ZoneId.systemDefault())
        .format(Instant.parse(value))
}.getOrNull()

@Composable
private fun LoadingState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
private fun RetryState(message: String, retry: () -> Unit) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(message, color = MaterialTheme.colorScheme.error)
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = retry) { Text("Повторить") }
    }
}

@Composable
private fun EmptyState(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
    }
}
