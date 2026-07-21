package frezzy.gonow.features.tasks

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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

@Composable
fun TasksTab(mapViewModel: ActivityMapViewModel) {
    var searchQuery by remember { mutableStateOf("") }

    val items = remember(mapViewModel.activities, searchQuery) {
        val q = searchQuery.trim()
        if (q.isEmpty()) mapViewModel.activities
        else mapViewModel.activities.filter {
            it.title.contains(q, ignoreCase = true) || it.parsedCategory.titleRu.contains(q, ignoreCase = true)
        }
    }

    AuthBackdrop {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 48.dp)
        ) {
            Spacer(modifier = Modifier.height(24.dp))

            Text(
                text = "Активности",
                style = MaterialTheme.typography.headlineLarge
            )

            Text(
                text = "Поблизости",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Search
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                placeholder = { Text("Поиск активностей...") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (searchQuery.isNotEmpty()) {
                        IconButton(onClick = { searchQuery = "" }) {
                            Icon(Icons.Filled.Close, contentDescription = "Очистить")
                        }
                    }
                },
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Content
            when {
                mapViewModel.state == MapContentState.Loading && items.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(modifier = Modifier.height(12.dp))
                            Text("Загружаем...", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                items.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Filled.Explore,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(48.dp)
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = if (searchQuery.isNotEmpty()) "Ничего не найдено" else "Активностей пока нет",
                                style = MaterialTheme.typography.bodyLarge
                            )
                            Text(
                                text = if (searchQuery.isNotEmpty()) "Попробуйте другой запрос" else "Создайте первую активность на карте!",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(items, key = { it.id }) { activity ->
                            ActivityListCard(activity = activity)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ActivityListCard(activity: MapActivityResponse) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Category icon
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(categoryColor(activity.parsedCategory)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = categoryListIcon(activity.parsedCategory),
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(22.dp)
                )
            }

            // Content
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
                    fontWeight = FontWeight.SemiBold,
                    color = categoryColor(activity.parsedCategory)
                )
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    activity.startsAt?.let { startsAt ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(formatTime(startsAt), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.People, contentDescription = null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(modifier = Modifier.width(4.dp))
                        val txt = activity.participantLimit?.let { "${activity.participantCount}/$it" } ?: "${activity.participantCount}"
                        Text(txt, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    activity.distanceMeters?.let { dist ->
                        if (dist > 0) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.LocationOn, contentDescription = null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(formatDist(dist), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }

            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

private fun formatTime(iso: String): String {
    return try {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val output = SimpleDateFormat("d MMM, HH:mm", Locale("ru"))
        input.parse(iso)?.let { output.format(it) } ?: iso
    } catch (_: Exception) { iso }
}

private fun formatDist(meters: Double): String =
    if (meters < 1000) "${meters.toInt()} м" else String.format("%.1f км", meters / 1000)

private fun categoryColor(cat: ActivityCategory) = when (cat) {
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

private fun categoryListIcon(cat: ActivityCategory) = when (cat) {
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
