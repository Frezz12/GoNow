package frezzy.gonow.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.models.ProfileStatus
import frezzy.gonow.models.User
import frezzy.gonow.ui.auth.AuthViewModel
import frezzy.gonow.ui.theme.*

data class BottomNavItem(
    val index: Int,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

@Composable
fun MainScreen(
    user: User?,
    avatarBytes: ByteArray?,
    viewModel: AuthViewModel,
    weatherViewModel: WeatherViewModel,
    locationProvider: DeviceLocationProvider,
    settingsPrefs: SettingsPrefs,
    onLogout: () -> Unit
) {
    val items = listOf(
        BottomNavItem(0, "Карта", Icons.Filled.Map, Icons.Outlined.Map),
        BottomNavItem(1, "Задания", Icons.Filled.Checklist, Icons.Outlined.Checklist),
        BottomNavItem(2, "Чат", Icons.Filled.Chat, Icons.Outlined.Chat),
        BottomNavItem(3, "Профиль", Icons.Filled.Person, Icons.Outlined.Person)
    )

    var selectedTab by remember { mutableIntStateOf(0) }
    var showCreateSheet by remember { mutableStateOf(false) }
    var showProfileEditor by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showProfileRequiredAlert by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Color.Transparent,
            bottomBar = {
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    tonalElevation = 0.dp
                ) {
                    items.forEachIndexed { index, item ->
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == item.index) item.selectedIcon else item.unselectedIcon,
                                    contentDescription = item.label
                                )
                            },
                            label = { Text(item.label, fontSize = 11.sp) },
                            selected = selectedTab == item.index,
                            onClick = { selectedTab = item.index },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                            )
                        )
                    }
                }
            }
        ) { padding ->
            Box(modifier = Modifier.padding(padding)) {
                when (selectedTab) {
                    0 -> MapTab(
                        user = user,
                        avatarBytes = avatarBytes,
                        onNavigateToProfile = { selectedTab = 3 },
                        weatherViewModel = weatherViewModel,
                        locationProvider = locationProvider,
                        settingsPrefs = settingsPrefs
                    )
                    1 -> TasksTab()
                    2 -> ChatTab()
                    3 -> ProfileTab(
                        user = user,
                        avatarBytes = avatarBytes,
                        profilePhotos = viewModel.uiState.profilePhotos.photos,
                        photoContentMap = viewModel.uiState.photoContentMap,
                        onRefresh = { viewModel.refreshProfile() },
                        onLogout = onLogout,
                        onEditProfile = { showProfileEditor = true },
                        onSettings = { showSettings = true },
                        onUploadAvatar = { viewModel.uploadAvatar(it) },
                        onUploadPhoto = { viewModel.uploadPhoto(it) },
                        onDeletePhoto = { viewModel.deletePhoto(it) },
                        onLoadPhotoContent = { viewModel.loadPhotoContent(it) },
                        isLoading = viewModel.uiState.isLoading
                    )
                }
            }
        }

        // Floating "Создать" button — only on Map tab
        if (selectedTab == 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 152.dp)
            ) {
                val shape = RoundedCornerShape(26.dp)

                Surface(
                    onClick = {
                        if (user?.profileStatus == ProfileStatus.REQUIRED) {
                            showProfileRequiredAlert = true
                        } else {
                            showCreateSheet = true
                        }
                    },
                    shape = shape,
                    color = MaterialTheme.colorScheme.primary,
                    shadowElevation = 6.dp
                ) {
                    Row(
                        modifier = Modifier
                            .padding(horizontal = 18.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(20.dp))
                        Text("Создать", color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                }
            }
        }
    }

    if (showCreateSheet) {
        CreateTaskSheet(onDismiss = { showCreateSheet = false })
    }

    if (showProfileEditor && user != null) {
        ProfileEditorSheet(
            user = user,
            avatarBytes = avatarBytes,
            onSave = { request -> viewModel.updateProfile(request); showProfileEditor = false },
            onUploadAvatar = { viewModel.uploadAvatar(it) },
            onDismiss = { showProfileEditor = false },
            isLoading = viewModel.uiState.isLoading,
            errorMessage = viewModel.uiState.errorMessage
        )
    }

    if (showSettings) {
        SettingsSheet(
            settingsPrefs = settingsPrefs,
            onDismiss = { showSettings = false },
            onLogout = { showSettings = false; onLogout() }
        )
    }

    if (showProfileRequiredAlert) {
        AlertDialog(
            onDismissRequest = { showProfileRequiredAlert = false },
            title = { Text("Сначала заполните профиль") },
            text = { Text("Укажите дату рождения, чтобы создавать задания и подавать заявки на активности.") },
            confirmButton = {
                TextButton(onClick = { showProfileRequiredAlert = false; selectedTab = 3 }) {
                    Text("Перейти в профиль")
                }
            },
            dismissButton = {
                TextButton(onClick = { showProfileRequiredAlert = false }) {
                    Text("Позже")
                }
            }
        )
    }
}
