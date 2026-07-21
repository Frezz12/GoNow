package frezzy.gonow.features.map

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
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

@Composable
fun ActivityMapCard(
    activity: MapActivityResponse,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    GlassCard(modifier = modifier.fillMaxWidth()) {
        // Header row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Category icon
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = categoryIcon(activity.parsedCategory),
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }

            // Title + category
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = activity.title,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    maxLines = 2
                )
                Text(
                    text = activity.parsedCategory.titleRu,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Close button
            IconButton(
                onClick = onClose,
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Закрыть",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Metadata row
        Row(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            activity.startsAt?.let { startsAt ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.AccessTime,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = formatActivityTime(startsAt),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.People,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                val participantsText = if (activity.participantLimit != null) {
                    "${activity.participantCount}/${activity.participantLimit}"
                } else {
                    "${activity.participantCount}"
                }
                Text(
                    text = participantsText,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            activity.distanceMeters?.let { distance ->
                if (distance > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.LocationOn,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = formatDistance(distance),
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Open button
        GradientPrimaryButton(
            text = "Открыть",
            onClick = { /* TODO: open activity detail */ },
            modifier = Modifier.fillMaxWidth()
        )
    }
}

private fun formatActivityTime(isoString: String): String {
    return try {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val output = SimpleDateFormat("d MMM, HH:mm", Locale("ru"))
        val date = input.parse(isoString)
        date?.let { output.format(it) } ?: isoString
    } catch (_: Exception) {
        isoString
    }
}

private fun formatDistance(meters: Double): String {
    return if (meters < 1000) {
        "${meters.toInt()} м"
    } else {
        String.format("%.1f км", meters / 1000)
    }
}

private fun categoryIcon(category: ActivityCategory) = when (category) {
    ActivityCategory.WALKING -> Icons.Filled.DirectionsWalk
    ActivityCategory.SPORT -> Icons.Filled.DirectionsRun
    ActivityCategory.TRAVEL -> Icons.Filled.Flight
    ActivityCategory.MUSIC -> Icons.Filled.MusicNote
    ActivityCategory.GAMES -> Icons.Filled.SportsEsports
    ActivityCategory.FOOD -> Icons.Filled.Restaurant
    ActivityCategory.HELP -> Icons.Filled.Handshake
    ActivityCategory.EDUCATION -> Icons.Filled.MenuBook
    ActivityCategory.ANIMALS -> Icons.Filled.Pets
    ActivityCategory.EVENT -> Icons.Filled.Event
    ActivityCategory.OTHER -> Icons.Filled.AutoAwesome
}
