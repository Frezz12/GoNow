package frezzy.gonow.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import frezzy.gonow.R
import frezzy.gonow.core.AppLanguage
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.cancellableRunCatching
import frezzy.gonow.data.NotificationRepository
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.models.NotificationPreferences
import frezzy.gonow.models.SocialPrivacy
import frezzy.gonow.models.SocialPrivacySettings
import frezzy.gonow.ui.theme.AuthBackdrop
import frezzy.gonow.ui.theme.GlassCard
import frezzy.gonow.ui.theme.GradientPrimaryButton
import kotlinx.coroutines.launch

private enum class SettingsPage { ROOT, PRIVACY, NOTIFICATIONS }

@Composable
fun SettingsSheet(
    settingsPrefs: SettingsPrefs,
    notificationRepository: NotificationRepository,
    socialRepository: SocialRepository,
    onDismiss: () -> Unit,
    onLogout: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val themeMode by settingsPrefs.themeMode
    val temperatureUnit by settingsPrefs.temperatureUnit
    val useProfileLocation by settingsPrefs.useProfileLocation
    val language by settingsPrefs.language
    var notificationPreferences by remember { mutableStateOf<NotificationPreferences?>(null) }
    var privacySettings by remember { mutableStateOf<SocialPrivacySettings?>(null) }
    var privacyDraft by remember { mutableStateOf<SocialPrivacySettings?>(null) }
    var settingsError by remember { mutableStateOf<String?>(null) }
    var languageExpanded by remember { mutableStateOf(false) }
    var page by remember { mutableStateOf(SettingsPage.ROOT) }
    var savingPrivacy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        cancellableRunCatching { notificationRepository.getPreferences() }
            .onSuccess { notificationPreferences = it }
            .onFailure { settingsError = it.message }
        cancellableRunCatching { socialRepository.getPrivacy() }
            .onSuccess { privacySettings = it; privacyDraft = it }
            .onFailure { settingsError = it.message }
    }

    fun saveNotifications(value: NotificationPreferences) {
        notificationPreferences = value
        scope.launch {
            cancellableRunCatching { notificationRepository.updatePreferences(value) }
                .onSuccess { notificationPreferences = it }
                .onFailure { settingsError = it.message }
        }
    }

    fun savePrivacy() {
        val value = privacyDraft ?: return
        savingPrivacy = true
        scope.launch {
            cancellableRunCatching { socialRepository.updatePrivacy(value) }
                .onSuccess { privacySettings = it; privacyDraft = it }
                .onFailure { settingsError = it.message }
            savingPrivacy = false
        }
    }

    val title = when (page) {
        SettingsPage.ROOT -> "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438"
        SettingsPage.PRIVACY -> "\u041a\u043e\u043d\u0444\u0438\u0434\u0435\u043d\u0446\u0438\u0430\u043b\u044c\u043d\u043e\u0441\u0442\u044c"
        SettingsPage.NOTIFICATIONS -> "\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f"
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        AuthBackdrop {
            Scaffold(
                containerColor = androidx.compose.ui.graphics.Color.Transparent,
                topBar = {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .statusBarsPadding()
                            .padding(horizontal = 20.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Surface(
                            onClick = { if (page == SettingsPage.ROOT) onDismiss() else page = SettingsPage.ROOT },
                            modifier = Modifier.size(48.dp),
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
                            shadowElevation = 5.dp
                        ) {
                            Icon(
                                if (page == SettingsPage.ROOT) Icons.Default.Close else Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = if (page == SettingsPage.ROOT) "\u0417\u0430\u043a\u0440\u044b\u0442\u044c" else "\u041d\u0430\u0437\u0430\u0434",
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                        Text(
                            title,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                        Spacer(Modifier.size(48.dp))
                    }
                }
            ) { padding ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    when (page) {
                        SettingsPage.ROOT -> SettingsRoot(
                            themeMode = themeMode,
                            onThemeChange = settingsPrefs::setThemeMode,
                            language = language,
                            languageExpanded = languageExpanded,
                            onLanguageExpanded = { languageExpanded = it },
                            onLanguageChange = settingsPrefs::setLanguage,
                            useProfileLocation = useProfileLocation,
                            onUseProfileLocationChange = settingsPrefs::setUseProfileLocation,
                            temperatureUnit = temperatureUnit,
                            onTemperatureUnitChange = settingsPrefs::setTemperatureUnit,
                            onOpenPrivacy = { page = SettingsPage.PRIVACY },
                            onOpenNotifications = { page = SettingsPage.NOTIFICATIONS },
                            onLogout = onLogout
                        )

                        SettingsPage.PRIVACY -> PrivacyPage(
                            value = privacyDraft,
                            savedValue = privacySettings,
                            saving = savingPrivacy,
                            onChange = { privacyDraft = it },
                            onSave = ::savePrivacy
                        )

                        SettingsPage.NOTIFICATIONS -> NotificationsPage(
                            preferences = notificationPreferences,
                            onChange = ::saveNotifications
                        )
                    }
                    settingsError?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }
        }
    }
}

@Composable
private fun SettingsRoot(
    themeMode: Int,
    onThemeChange: (Int) -> Unit,
    language: AppLanguage,
    languageExpanded: Boolean,
    onLanguageExpanded: (Boolean) -> Unit,
    onLanguageChange: (AppLanguage) -> Unit,
    useProfileLocation: Boolean,
    onUseProfileLocationChange: (Boolean) -> Unit,
    temperatureUnit: Int,
    onTemperatureUnitChange: (Int) -> Unit,
    onOpenPrivacy: () -> Unit,
    onOpenNotifications: () -> Unit,
    onLogout: () -> Unit
) {
    SettingsCard(Icons.Default.Palette, "\u041e\u0444\u043e\u0440\u043c\u043b\u0435\u043d\u0438\u0435") {
        Text("\u0422\u0435\u043c\u0430 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u044f \u0441\u043b\u0435\u0434\u0443\u0435\u0442 \u0437\u0430 \u0432\u0430\u0448\u0438\u043c \u0432\u044b\u0431\u043e\u0440\u043e\u043c.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ChoiceRow(listOf("\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u0430\u044f", "\u0421\u0432\u0435\u0442\u043b\u0430\u044f", "\u0422\u0451\u043c\u043d\u0430\u044f"), themeMode, onThemeChange)
    }

    Box {
        SettingsNavigationCard(
            icon = Icons.Default.Language,
            title = "\u042f\u0437\u044b\u043a \u0438 \u0440\u0435\u0433\u0438\u043e\u043d",
            subtitle = if (language == AppLanguage.SYSTEM) "\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0439" else language.displayName,
            onClick = { onLanguageExpanded(true) }
        )
        DropdownMenu(expanded = languageExpanded, onDismissRequest = { onLanguageExpanded(false) }) {
            AppLanguage.entries.forEach { value ->
                DropdownMenuItem(
                    text = { Text(if (value == AppLanguage.SYSTEM) "\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0439" else value.displayName) },
                    onClick = { onLanguageExpanded(false); onLanguageChange(value) }
                )
            }
        }
    }

    SettingsNavigationCard(
        icon = Icons.Default.PrivacyTip,
        title = "\u041a\u043e\u043d\u0444\u0438\u0434\u0435\u043d\u0446\u0438\u0430\u043b\u044c\u043d\u043e\u0441\u0442\u044c",
        subtitle = "\u041a\u0442\u043e \u043c\u043e\u0436\u0435\u0442 \u043f\u0438\u0441\u0430\u0442\u044c \u0438 \u043f\u0440\u0438\u0433\u043b\u0430\u0448\u0430\u0442\u044c \u0432\u0430\u0441",
        onClick = onOpenPrivacy
    )

    SettingsCard(Icons.Default.WbSunny, "\u041f\u043e\u0433\u043e\u0434\u0430") {
        SettingsToggle("\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u044c \u0433\u043e\u0440\u043e\u0434 \u043f\u0440\u043e\u0444\u0438\u043b\u044f", useProfileLocation, onChange = onUseProfileLocationChange)
        Text("\u0415\u0434\u0438\u043d\u0438\u0446\u044b \u0442\u0435\u043c\u043f\u0435\u0440\u0430\u0442\u0443\u0440\u044b \u0434\u043b\u044f \u0432\u0438\u0434\u0436\u0435\u0442\u0430 \u043d\u0430 \u043a\u0430\u0440\u0442\u0435.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ChoiceRow(listOf("\u0410\u0432\u0442\u043e", "\u00b0C", "\u00b0F"), temperatureUnit, onTemperatureUnitChange)
    }

    SettingsNavigationCard(
        icon = Icons.Default.Notifications,
        title = "\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f",
        subtitle = "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u0446\u0435\u043d\u0442\u0440\u0430 \u0438 realtime-\u0441\u043e\u0431\u044b\u0442\u0438\u0439",
        onClick = onOpenNotifications
    )

    SettingsCard(Icons.Default.Person, "\u0410\u043a\u043a\u0430\u0443\u043d\u0442") {
        Text("\u0412\u044b\u0445\u043e\u0434 \u0437\u0430\u0432\u0435\u0440\u0448\u0438\u0442 \u0441\u0435\u0441\u0441\u0438\u044e \u0442\u043e\u043b\u044c\u043a\u043e \u043d\u0430 \u044d\u0442\u043e\u043c \u0443\u0441\u0442\u0440\u043e\u0439\u0441\u0442\u0432\u0435.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(
            onClick = onLogout,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
        ) { Text("\u0412\u044b\u0439\u0442\u0438") }
    }
}

@Composable
private fun PrivacyPage(
    value: SocialPrivacySettings?,
    savedValue: SocialPrivacySettings?,
    saving: Boolean,
    onChange: (SocialPrivacySettings) -> Unit,
    onSave: () -> Unit
) {
    SettingsCard(Icons.Default.GppGood, "\u041b\u0438\u0447\u043d\u044b\u0435 \u0433\u0440\u0430\u043d\u0438\u0446\u044b") {
        Text("\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u043f\u0440\u0438\u043c\u0435\u043d\u044f\u044e\u0442\u0441\u044f \u043a\u043e \u0432\u0441\u0435\u043c \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u043c \u0441\u0440\u0430\u0437\u0443. \u0414\u0440\u0443\u0437\u044c\u044f \u0432\u0441\u0435\u0433\u0434\u0430 \u043c\u043e\u0433\u0443\u0442 \u043f\u0440\u043e\u0434\u043e\u043b\u0436\u0438\u0442\u044c \u0443\u0436\u0435 \u0441\u043e\u0437\u0434\u0430\u043d\u043d\u044b\u0439 \u0447\u0430\u0442.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    value?.let { privacy ->
        SettingsCard(Icons.Default.ChatBubble, "\u041a\u0442\u043e \u043c\u043e\u0436\u0435\u0442 \u043d\u0430\u043f\u0438\u0441\u0430\u0442\u044c") {
            PrivacySelector(privacy.messagePrivacy) { onChange(privacy.copy(messagePrivacy = it)) }
            Text("\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435, \u043a\u0442\u043e \u0441\u043c\u043e\u0436\u0435\u0442 \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u0441 \u0432\u0430\u043c\u0438 \u043d\u043e\u0432\u044b\u0439 \u0447\u0430\u0442.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        @Suppress("DEPRECATION")
        SettingsCard(Icons.Default.DirectionsRun, "\u041a\u0442\u043e \u043c\u043e\u0436\u0435\u0442 \u043f\u0440\u0438\u0433\u043b\u0430\u0441\u0438\u0442\u044c") {
            PrivacySelector(privacy.invitationPrivacy) { onChange(privacy.copy(invitationPrivacy = it)) }
            Text("\u041c\u0435\u0436\u0434\u0443 \u0434\u0432\u0443\u043c\u044f \u043b\u044e\u0434\u044c\u043c\u0438 \u043c\u043e\u0436\u0435\u0442 \u0431\u044b\u0442\u044c \u0442\u043e\u043b\u044c\u043a\u043e \u043e\u0434\u043d\u043e \u0430\u043a\u0442\u0438\u0432\u043d\u043e\u0435 \u043f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u0435.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        GradientPrimaryButton(
            text = if (value == savedValue) "\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e" else "\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c",
            onClick = onSave,
            enabled = value != savedValue,
            loading = saving
        )
    } ?: Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun NotificationsPage(preferences: NotificationPreferences?, onChange: (NotificationPreferences) -> Unit) {
    preferences?.let { value ->
        SettingsCard(Icons.Default.Notifications, "\u0426\u0435\u043d\u0442\u0440 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0439") {
            Text("\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0435 push-\u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u043f\u043e\u043a\u0430 \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b \u043d\u0430 Android; \u0446\u0435\u043d\u0442\u0440 \u0438 realtime \u0432\u043d\u0443\u0442\u0440\u0438 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u044f \u0440\u0430\u0431\u043e\u0442\u0430\u044e\u0442.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            SettingsToggle("\u0417\u0430\u044f\u0432\u043a\u0438 \u0432 \u0434\u0440\u0443\u0437\u044c\u044f", value.friendRequests) { onChange(value.copy(friendRequests = it)) }
            SettingsToggle("\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f", value.messages) { onChange(value.copy(messages = it)) }
            SettingsToggle("\u041f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u044f", value.invitations) { onChange(value.copy(invitations = it)) }
            SettingsToggle("\u0410\u043a\u0442\u0438\u0432\u043d\u043e\u0441\u0442\u0438", value.activities) { onChange(value.copy(activities = it)) }
            SettingsToggle("\u0417\u0432\u0443\u043a realtime", value.soundEnabled) { onChange(value.copy(soundEnabled = it)) }
        }
    } ?: CircularProgressIndicator(modifier = Modifier.padding(24.dp).wrapContentWidth())
}

@Composable
private fun SettingsCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                    Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(9.dp).size(22.dp))
                }
                Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            }
            content()
        }
    }
}

@Composable
private fun SettingsNavigationCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    GlassCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(10.dp).size(24.dp))
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ChoiceRow(values: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        values.forEachIndexed { index, label ->
            val selectedColor = if (selected == index) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant
            val textColor = if (selected == index) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
            Surface(
                modifier = Modifier.weight(1f).heightIn(min = 50.dp).selectable(selected = selected == index, onClick = { onSelect(index) }, role = Role.RadioButton),
                shape = RoundedCornerShape(16.dp),
                color = selectedColor
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp)) {
                    Text(label, color = textColor, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun SettingsToggle(title: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

@Composable
private fun PrivacySelector(value: SocialPrivacy, onChange: (SocialPrivacy) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    fun label(option: SocialPrivacy) = when (option) {
        SocialPrivacy.EVERYONE -> "\u0412\u0441\u0435"
        SocialPrivacy.FRIENDS -> "\u0422\u043e\u043b\u044c\u043a\u043e \u0434\u0440\u0443\u0437\u044c\u044f"
        SocialPrivacy.VERIFIED -> "\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0451\u043d\u043d\u044b\u0435"
        SocialPrivacy.NOBODY -> "\u041d\u0438\u043a\u0442\u043e"
    }
    Box {
        Surface(
            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { expanded = true },
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceVariant
        ) {
            Row(modifier = Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(label(value), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Icon(Icons.Default.UnfoldMore, contentDescription = "\u0412\u044b\u0431\u0440\u0430\u0442\u044c")
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SocialPrivacy.entries.forEach { option ->
                DropdownMenuItem(text = { Text(label(option)) }, onClick = { expanded = false; onChange(option) })
            }
        }
    }
}
