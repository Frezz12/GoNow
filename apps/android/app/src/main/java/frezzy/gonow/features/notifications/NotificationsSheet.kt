package frezzy.gonow.features.notifications

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
import frezzy.gonow.models.GoNowNotification
import frezzy.gonow.models.NotificationCategory
import frezzy.gonow.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationsSheet(onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        NotificationsContent(onDismiss = onDismiss)
    }
}

@Composable
private fun NotificationsContent(onDismiss: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val viewModel = remember {
        NotificationsViewModel(
            frezzy.gonow.data.NotificationRepository(
                frezzy.gonow.network.ApiClient(frezzy.gonow.data.TokenStore(context.applicationContext))
            )
        )
    }

    LaunchedEffect(Unit) { viewModel.load() }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp)
    ) {
        // Header
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Уведомления", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
            if (viewModel.unreadCount > 0) {
                TextButton(onClick = { viewModel.markAllRead() }) {
                    Text("Прочитать всё", fontSize = 13.sp)
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Filter bar
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NotificationFilter.entries.forEach { f ->
                val isSelected = viewModel.filter == f
                FilterChip(
                    selected = isSelected,
                    onClick = { viewModel.selectFilter(f) },
                    label = { Text(f.titleRu, fontSize = 12.sp) }
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Content
        when {
            viewModel.isLoading -> {
                Box(modifier = Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            viewModel.filteredNotifications.isEmpty() -> {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            if (viewModel.filter == NotificationFilter.UNREAD) Icons.Filled.CheckCircle else Icons.Filled.NotificationsOff,
                            contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(40.dp)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            if (viewModel.filter == NotificationFilter.UNREAD) "Всё прочитано" else "Пока тихо",
                            fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            else -> {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (viewModel.todayNotifications.isNotEmpty()) {
                        item { Text("Сегодня", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 4.dp)) }
                        items(viewModel.todayNotifications, key = { it.id }) { notif ->
                            NotificationRow(notification = notif, onRead = { viewModel.markRead(notif) }, onDelete = { viewModel.delete(notif) })
                        }
                    }
                    if (viewModel.earlierNotifications.isNotEmpty()) {
                        item { Text("Ранее", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 4.dp)) }
                        items(viewModel.earlierNotifications, key = { it.id }) { notif ->
                            NotificationRow(notification = notif, onRead = { viewModel.markRead(notif) }, onDelete = { viewModel.delete(notif) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NotificationRow(notification: GoNowNotification, onRead: () -> Unit, onDelete: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Category icon
        Box(
            modifier = Modifier.size(40.dp).clip(CircleShape).background(categoryColor(notification.parsedCategory).copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                categoryIcon(notification.parsedCategory),
                contentDescription = null,
                tint = categoryColor(notification.parsedCategory),
                modifier = Modifier.size(18.dp)
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = notification.title,
                fontWeight = if (notification.isRead) FontWeight.Medium else FontWeight.Bold,
                fontSize = 14.sp
            )
            Text(
                text = notification.body,
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = formatNotifTime(notification.createdAt),
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }

        // Unread dot
        if (!notification.isRead) {
            Box(
                modifier = Modifier.padding(top = 4.dp).size(10.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}

private fun categoryColor(cat: NotificationCategory) = when (cat) {
    NotificationCategory.SOCIAL -> Color(0xFFE85CA8)
    NotificationCategory.MESSAGES -> Color(0xFF239DCC)
    NotificationCategory.ACTIVITIES -> Color(0xFF229F72)
    NotificationCategory.SYSTEM -> Color(0xFFC68D1B)
}

private fun categoryIcon(cat: NotificationCategory) = when (cat) {
    NotificationCategory.SOCIAL -> Icons.Filled.People
    NotificationCategory.MESSAGES -> Icons.Filled.Message
    NotificationCategory.ACTIVITIES -> Icons.Filled.Sports
    NotificationCategory.SYSTEM -> Icons.Filled.Info
}

private fun formatNotifTime(iso: String): String {
    return try {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val date = input.parse(iso) ?: return iso
        val now = Date()
        val diffMs = now.time - date.time
        val diffMin = diffMs / 60000
        when {
            diffMin < 1 -> "только что"
            diffMin < 60 -> "${diffMin} мин назад"
            diffMin < 1440 -> "${diffMin / 60} ч назад"
            else -> SimpleDateFormat("d MMM", Locale("ru")).format(date)
        }
    } catch (_: Exception) { iso }
}
