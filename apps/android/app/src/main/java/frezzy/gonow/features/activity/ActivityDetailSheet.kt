package frezzy.gonow.features.activity

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import frezzy.gonow.models.ActivityCategory
import frezzy.gonow.models.MapActivityResponse
import frezzy.gonow.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    activity: MapActivityResponse,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp)
        ) {
            // Header with category icon
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(categoryDetailColor(activity.parsedCategory)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = categoryDetailIcon(activity.parsedCategory),
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(24.dp)
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = activity.title,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp
                    )
                    Text(
                        text = activity.parsedCategory.titleRu,
                        fontSize = 14.sp,
                        color = categoryDetailColor(activity.parsedCategory),
                        fontWeight = FontWeight.SemiBold
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Закрыть")
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Info card
            GlassCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Date & Time
                    activity.startsAt?.let { startsAt ->
                        DetailRow(
                            icon = Icons.Filled.CalendarToday,
                            label = "Когда",
                            value = formatDetailTime(startsAt)
                        )
                    }

                    // Participants
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                    DetailRow(
                        icon = Icons.Filled.People,
                        label = "Участники",
                        value = activity.participantLimit?.let {
                            "${activity.participantCount} из $it мест"
                        } ?: "${activity.participantCount} участников"
                    )

                    // Distance
                    activity.distanceMeters?.let { dist ->
                        if (dist > 0) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                            DetailRow(
                                icon = Icons.Filled.LocationOn,
                                label = "Расстояние",
                                value = formatDetailDist(dist)
                            )
                        }
                    }

                    // Joined status
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                    DetailRow(
                        icon = if (activity.isJoined) Icons.Filled.CheckCircle else Icons.Filled.PersonAdd,
                        label = "Статус",
                        value = if (activity.isJoined) "Вы участвуете" else "Можно присоединиться"
                    )

                    // Full warning
                    if (activity.isFull) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                Icons.Filled.Warning,
                                contentDescription = null,
                                tint = Warning,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = "Места закончились",
                                fontSize = 14.sp,
                                color = Warning,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Action button
            if (activity.isJoined) {
                OutlinedButton(
                    onClick = { /* TODO: open chat */ },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Icon(Icons.Filled.Chat, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Открыть чат")
                }
            } else if (!activity.isFull) {
                GradientPrimaryButton(
                    text = "Присоединиться",
                    onClick = { /* TODO: apply to activity */ }
                )
            } else {
                OutlinedButton(
                    onClick = {},
                    modifier = Modifier.fillMaxWidth(),
                    enabled = false,
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text("Нет свободных мест")
                }
            }
        }
    }
}

@Composable
private fun DetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp)
        )
        Column {
            Text(
                text = label,
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

private fun formatDetailTime(iso: String): String {
    return try {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val output = SimpleDateFormat("d MMMM yyyy, HH:mm", Locale("ru"))
        input.parse(iso)?.let { output.format(it) } ?: iso
    } catch (_: Exception) { iso }
}

private fun formatDetailDist(meters: Double): String =
    if (meters < 1000) "${meters.toInt()} м" else String.format("%.1f км", meters / 1000)

private fun categoryDetailColor(cat: ActivityCategory) = when (cat) {
    ActivityCategory.WALKING -> Color(0xFF4CAF50)
    ActivityCategory.SPORT -> Color(0xFFF44336)
    ActivityCategory.TRAVEL -> Color(0xFF2196F3)
    ActivityCategory.MUSIC -> Color(0xFF9C27B0)
    ActivityCategory.GAMES -> Color(0xFF3F51B5)
    ActivityCategory.FOOD -> Color(0xFFFF9800)
    ActivityCategory.HELP -> Color(0xFF009688)
    ActivityCategory.EDUCATION -> Color(0xFF795548)
    ActivityCategory.ANIMALS -> Color(0xFF00C853)
    ActivityCategory.EVENT -> Color(0xFFE91E63)
    ActivityCategory.OTHER -> Color(0xFF9E9E9E)
}

private fun categoryDetailIcon(cat: ActivityCategory) = when (cat) {
    ActivityCategory.WALKING -> Icons.Filled.DirectionsWalk
    ActivityCategory.SPORT -> Icons.Filled.Sports
    ActivityCategory.TRAVEL -> Icons.Filled.Flight
    ActivityCategory.MUSIC -> Icons.Filled.MusicNote
    ActivityCategory.GAMES -> Icons.Filled.SportsEsports
    ActivityCategory.FOOD -> Icons.Filled.Restaurant
    ActivityCategory.HELP -> Icons.Filled.Handshake
    ActivityCategory.EDUCATION -> Icons.Filled.School
    ActivityCategory.ANIMALS -> Icons.Filled.Pets
    ActivityCategory.EVENT -> Icons.Filled.Event
    ActivityCategory.OTHER -> Icons.Filled.AutoAwesome
}
