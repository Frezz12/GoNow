package frezzy.gonow.features.social

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.MeetingInvitation
import frezzy.gonow.models.SocialUser
import frezzy.gonow.ui.theme.*

enum class SocialSection(val titleRu: String) {
    PEOPLE("Люди"), FRIENDS("Друзья"), INVITATIONS("Встречи")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SocialHubSheet(onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        SocialHubContent(onDismiss = onDismiss)
    }
}

@Composable
private fun SocialHubContent(onDismiss: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var section by remember { mutableStateOf(SocialSection.PEOPLE) }
    var people by remember { mutableStateOf<List<SocialUser>>(emptyList()) }
    var invitations by remember { mutableStateOf<List<MeetingInvitation>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        isLoading = true
        try {
            val repo = frezzy.gonow.data.SocialRepository(
                frezzy.gonow.network.ApiClient(frezzy.gonow.data.TokenStore(context.applicationContext))
            )
            people = repo.getPeople()
            invitations = repo.getInvitations()
        } catch (_: Exception) { }
        isLoading = false
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp)
    ) {
        Text("Люди и встречи", fontWeight = FontWeight.Bold, fontSize = 18.sp)

        Spacer(modifier = Modifier.height(12.dp))

        // Section tabs
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            SocialSection.entries.forEachIndexed { idx, s ->
                SegmentedButton(
                    selected = section == s,
                    onClick = { section = s },
                    shape = SegmentedButtonDefaults.itemShape(idx, SocialSection.entries.size)
                ) { Text(s.titleRu, fontSize = 13.sp) }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        when (section) {
            SocialSection.PEOPLE -> {
                // Search
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    placeholder = { Text("Имя, username или город") },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                )
                Spacer(modifier = Modifier.height(12.dp))

                if (isLoading) {
                    Box(modifier = Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else {
                    val filtered = if (query.isBlank()) people else people.filter {
                        it.displayName.contains(query, ignoreCase = true) || it.username.contains(query, ignoreCase = true)
                    }
                    if (filtered.isEmpty()) {
                        EmptyStateView("Никого не найдено")
                    } else {
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            items(filtered, key = { it.id }) { user ->
                                SocialUserCard(user = user)
                            }
                        }
                    }
                }
            }
            SocialSection.FRIENDS -> {
                val friends = people.filter { it.isFriend }
                if (friends.isEmpty()) EmptyStateView("Список друзей пуст")
                else LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(friends, key = { it.id }) { user ->
                        SocialUserCard(user = user)
                    }
                }
            }
            SocialSection.INVITATIONS -> {
                if (invitations.isEmpty()) EmptyStateView("Нет приглашений")
                else LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(invitations, key = { it.id }) { inv ->
                        InvitationCard(invitation = inv)
                    }
                }
            }
        }
    }
}

@Composable
private fun SocialUserCard(user: SocialUser) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(modifier = Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                    Text(user.initials, color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(user.displayName, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    if (user.username.isNotBlank()) {
                        Text("@${user.username}", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Expandable info
            if (user.city != null || user.bio != null || user.interests.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Info, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Подробнее", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(modifier = Modifier.height(6.dp))
                user.city?.let { Text("📍 $it", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                user.bio?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (user.interests.isNotEmpty()) {
                    Text(user.interests.joinToString(", "), fontSize = 11.sp, color = MaterialTheme.colorScheme.primary)
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Action buttons
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { /* friend action */ },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(
                        when {
                            user.isFriend -> "Удалить"
                            user.isIncomingRequest -> "Принять"
                            user.hasPendingRequest -> "Отправлено"
                            else -> "В друзья"
                        },
                        fontSize = 13.sp
                    )
                }
                if (user.canMessage) {
                    IconButton(onClick = { /* start chat */ }, modifier = Modifier.size(40.dp)) {
                        Icon(Icons.Filled.Message, contentDescription = "Написать", modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun InvitationCard(invitation: MeetingInvitation) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (invitation.status == "pending") MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(modifier = Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.DirectionsWalk, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(invitation.templateTitle, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    Text(
                        if (invitation.isIncoming) "От ${invitation.senderName}" else "Для ${invitation.recipientName}",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    if (invitation.status == "pending") "Ожидает" else invitation.status,
                    fontSize = 12.sp, color = if (invitation.status == "accepted") Success else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            invitation.place?.let {
                if (it.isNotBlank()) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Text("📍 $it", fontSize = 13.sp)
                }
            }
            invitation.message?.let {
                if (it.isNotBlank()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun EmptyStateView(text: String) {
    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
    }
}
