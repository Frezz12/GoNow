package frezzy.gonow.ui.main

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.UpdateProfileRequest
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun ProfileEditorSheet(
    user: User,
    onSave: (UpdateProfileRequest) -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean,
    errorMessage: String?
) {
    var displayName by remember { mutableStateOf(user.displayName) }
    var city by remember { mutableStateOf(user.city ?: "") }
    var occupation by remember { mutableStateOf(user.occupation ?: "") }
    var bio by remember { mutableStateOf(user.bio ?: "") }
    var interests by remember { mutableStateOf(user.interests?.joinToString(", ") ?: "") }
    var relationshipStatus by remember { mutableStateOf(user.relationshipStatus ?: "") }
    var showBirthDatePicker by remember { mutableStateOf(user.birthDate != null) }
    var birthDate by remember { mutableStateOf(user.birthDate ?: "") }
    var localError by remember { mutableStateOf(errorMessage) }

    AuthBackdrop {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(32.dp))

            Text("Мой профиль", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(24.dp))

            // Name
            ProfileField(label = "Имя", value = displayName, onValueChange = { displayName = it })

            Spacer(Modifier.height(16.dp))

            // City
            ProfileField(label = "Город", value = city, onValueChange = { city = it })

            Spacer(Modifier.height(16.dp))

            // Occupation
            ProfileField(label = "Чем занимаетесь", value = occupation, onValueChange = { occupation = it })

            Spacer(Modifier.height(16.dp))

            // Relationship
            ProfileField(label = "Семейный статус", value = relationshipStatus, onValueChange = { relationshipStatus = it })

            Spacer(Modifier.height(16.dp))

            // Birth date
            Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.CalendarToday, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Text("Дата рождения обязательна", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                }
                Spacer(Modifier.height(8.dp))
                if (showBirthDatePicker && birthDate.isNotBlank()) {
                    ProfileField(label = "Дата рождения (ГГГГ-ММ-ДД)", value = birthDate, onValueChange = { birthDate = it })
                } else {
                    TextButton(onClick = { showBirthDatePicker = true; birthDate = "2000-01-01" }) {
                        Text("Указать дату рождения", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text("Без неё нельзя создавать задания.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Spacer(Modifier.height(16.dp))

            // Interests
            ProfileField(label = "Интересы", value = interests, onValueChange = { interests = it })
            Text("Через запятую: прогулки, кино, йога", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Spacer(Modifier.height(16.dp))

            // Bio
            Column {
                Text("О себе", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
                OutlinedTextField(
                    value = bio,
                    onValueChange = { if (it.length <= 500) bio = it },
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                    shape = RoundedCornerShape(18.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline, focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant, focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                         focusedTextColor = MaterialTheme.colorScheme.onSurface, unfocusedTextColor = MaterialTheme.colorScheme.onSurface
                    ),
                    supportingText = { Text("До 500 символов", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp) }
                )
            }

            Spacer(Modifier.height(16.dp))

            if (localError != null) {
                ErrorMessage(text = localError!!)
                Spacer(Modifier.height(8.dp))
            }

            GradientPrimaryButton(
                text = if (isLoading) "Сохраняем..." else "Сохранить профиль",
                onClick = {
                    if (displayName.trim().length < 2) { localError = "Введите имя не короче двух символов"; return@GradientPrimaryButton }
                    if (birthDate.isBlank() || !showBirthDatePicker) { localError = "Укажите дату рождения"; return@GradientPrimaryButton }
                    val parsedInterests = interests.split(",").map { it.trim() }.filter { it.isNotBlank() }
                    onSave(UpdateProfileRequest(
                        displayName = displayName.trim(),
                        birthDate = birthDate.trim().ifBlank { null },
                        city = city.trim().ifBlank { null },
                        occupation = occupation.trim().ifBlank { null },
                        bio = bio.trim().ifBlank { null },
                        interests = parsedInterests,
                        relationshipStatus = relationshipStatus.trim().ifBlank { null },
                        showDistance = user.showDistance ?: true
                    ))
                },
                enabled = !isLoading
            )

            Spacer(Modifier.height(12.dp))

            TextButton(onClick = onDismiss) {
                Text("Отмена", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Spacer(Modifier.height(32.dp))
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
                unfocusedBorderColor = MaterialTheme.colorScheme.outline, focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant, focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                 focusedTextColor = MaterialTheme.colorScheme.onSurface, unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant, focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            singleLine = true
        )
    }
}
