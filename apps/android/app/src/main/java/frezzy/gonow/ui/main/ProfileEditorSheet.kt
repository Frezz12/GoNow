package frezzy.gonow.ui.main

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.UpdateProfileRequest
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileEditorSheet(
    user: User,
    avatarBytes: ByteArray?,
    onSave: (UpdateProfileRequest) -> Unit,
    onUploadAvatar: (ByteArray) -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean,
    errorMessage: String?
) {
    val context = LocalContext.current
    var displayName by remember { mutableStateOf(user.displayName) }
    var city by remember { mutableStateOf(user.city ?: "") }
    var occupation by remember { mutableStateOf(user.occupation ?: "") }
    var bio by remember { mutableStateOf(user.bio ?: "") }
    var interests by remember { mutableStateOf(user.interests?.joinToString(", ") ?: "") }
    var relationshipStatus by remember { mutableStateOf(user.relationshipStatus ?: "") }
    var locationLabel by remember { mutableStateOf(user.locationLabel ?: "") }
    var showDistance by remember { mutableStateOf(user.showDistance ?: true) }
    var latitude by remember { mutableStateOf(user.latitude) }
    var longitude by remember { mutableStateOf(user.longitude) }
    var birthDate by remember { mutableStateOf(user.birthDate ?: "") }
    var showDatePicker by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf(errorMessage) }

    val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    val displayFormatter = DateTimeFormatter.ofPattern("d MMMM yyyy")

    val avatarPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri?.let {
            val bytes = context.contentResolver.openInputStream(it)?.use { s -> compressEditorBitmap(BitmapFactory.decodeStream(s), 1600) }
            if (bytes != null) onUploadAvatar(bytes)
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp)
        ) {
            // ─── Header with Save button ───
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Мой профиль", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                TextButton(
                    onClick = {
                        if (displayName.trim().length < 2) { localError = "Введите имя не короче двух символов"; return@TextButton }
                        if (birthDate.isBlank()) { localError = "Укажите дату рождения"; return@TextButton }
                        val parsedInterests = interests.split(",").map { it.trim() }.filter { it.isNotBlank() }
                        onSave(
                            UpdateProfileRequest(
                                displayName = displayName.trim(),
                                birthDate = birthDate.trim().ifBlank { null },
                                city = city.trim().ifBlank { null },
                                occupation = occupation.trim().ifBlank { null },
                                bio = bio.trim().ifBlank { null },
                                interests = parsedInterests,
                                relationshipStatus = relationshipStatus.trim().ifBlank { null },
                                locationLabel = locationLabel.trim().ifBlank { null },
                                latitude = latitude,
                                longitude = longitude,
                                showDistance = showDistance
                            )
                        )
                    },
                    enabled = !isLoading
                ) {
                    Text(
                        text = if (isLoading) "Сохранение..." else "Сохранить",
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 16.sp
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            // ─── Avatar section (like iOS) ───
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box {
                    ProfileAvatar(avatarBytes = avatarBytes, initials = user.initials, size = 72)
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape)
                            .clickable { avatarPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Filled.CameraAlt, contentDescription = "Изменить аватар", tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                }

                Spacer(Modifier.width(14.dp))

                Column {
                    Text(
                        "Фотография профиля",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        "Нажмите на аватар, чтобы выбрать фото.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(Modifier.height(24.dp))

            ProfileField(label = "Имя", value = displayName, onValueChange = { displayName = it })
            Spacer(Modifier.height(16.dp))

            ProfileField(label = "Город", value = city, onValueChange = { city = it })
            Spacer(Modifier.height(16.dp))

            ProfileField(label = "Чем занимаетесь", value = occupation, onValueChange = { occupation = it })
            Spacer(Modifier.height(16.dp))

            ProfileField(label = "Семейный статус", value = relationshipStatus, onValueChange = { relationshipStatus = it })
            Spacer(Modifier.height(16.dp))

            // ─── Location card ───
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.LocationOn, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text("Местоположение", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                    ProfileField(label = "Подпись к локации", value = locationLabel, onValueChange = { locationLabel = it })

                    if (latitude != null && longitude != null) {
                        Text(
                            "Координаты: ${String.format("%.4f", latitude)}, ${String.format("%.4f", longitude)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text("Показывать расстояние", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                            Text("Другие увидят расстояние до вас", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = showDistance, onCheckedChange = { showDistance = it })
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // ─── Birth date card with DatePicker ───
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.CalendarToday, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Text("Дата рождения обязательна", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }

                    val parsedDate = try {
                        LocalDate.parse(birthDate, dateFormatter)
                    } catch (_: Exception) { null }

                    if (parsedDate != null) {
                        OutlinedTextField(
                            value = parsedDate.format(displayFormatter),
                            onValueChange = {},
                            modifier = Modifier.fillMaxWidth().clickable { showDatePicker = true },
                            enabled = false,
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                disabledTextColor = MaterialTheme.colorScheme.onSurface,
                                disabledBorderColor = MaterialTheme.colorScheme.outline,
                                disabledContainerColor = MaterialTheme.colorScheme.surface,
                                disabledLabelColor = MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                            trailingIcon = {
                                Icon(Icons.Filled.EditCalendar, contentDescription = "Выбрать дату")
                            }
                        )
                    } else {
                        TextButton(onClick = { birthDate = "2000-01-01"; showDatePicker = true }) {
                            Text("Указать дату рождения", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                        }
                    }

                    Text("Без неё нельзя создавать задания.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Spacer(Modifier.height(16.dp))

            // ─── Interests ───
            ProfileField(label = "Интересы", value = interests, onValueChange = { interests = it })
            Spacer(Modifier.height(4.dp))
            Text(
                "Через запятую: прогулки, кино, йога",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(16.dp))

            // ─── Bio ───
            Column {
                Text("О себе", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
                OutlinedTextField(
                    value = bio,
                    onValueChange = { if (it.length <= 500) bio = it },
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                    shape = RoundedCornerShape(18.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        focusedTextColor = MaterialTheme.colorScheme.onSurface,
                        unfocusedTextColor = MaterialTheme.colorScheme.onSurface
                    )
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "До 500 символов",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(Modifier.height(16.dp))

            if (localError != null) {
                ErrorMessage(text = localError!!)
                Spacer(Modifier.height(8.dp))
            }

            Spacer(Modifier.height(8.dp))

            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                Text("Отмена", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    // ─── DatePicker Dialog ───
    if (showDatePicker) {
        val initialMillis = try {
            LocalDate.parse(birthDate, dateFormatter)
                .atStartOfDay(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
        } catch (_: Exception) {
            System.currentTimeMillis()
        }

        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Отмена")
                }
            }
        ) {
            val datePickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)

            LaunchedEffect(datePickerState.selectedDateMillis) {
                datePickerState.selectedDateMillis?.let { millis ->
                    val date = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
                    birthDate = date.format(dateFormatter)
                }
            }

            DatePicker(state = datePickerState)
        }
    }
}

@Composable
private fun ProfileField(label: String, value: String, onValueChange: (String) -> Unit) {
    Column {
        Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(18.dp),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            singleLine = true
        )
    }
}

private fun compressEditorBitmap(bitmap: Bitmap, maxSide: Int): ByteArray {
    val scale = if (maxOf(bitmap.width, bitmap.height) > maxSide) maxSide.toFloat() / maxOf(bitmap.width, bitmap.height) else 1f
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
    val stream = ByteArrayOutputStream()
    scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
    return stream.toByteArray()
}
