package frezzy.gonow.features.map

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.features.profile.ProfileAvatar
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.models.MapCoordinate
import frezzy.gonow.models.MapViewport
import frezzy.gonow.models.ProfileStatus
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*

@Composable
fun MapTab(
    user: User?,
    avatarBytes: ByteArray?,
    onNavigateToProfile: () -> Unit,
    onNotificationsTap: () -> Unit,
    weatherViewModel: WeatherViewModel,
    locationProvider: DeviceLocationProvider,
    settingsPrefs: SettingsPrefs,
    mapViewModel: ActivityMapViewModel,
    notificationUnreadCount: Int = 0,
    onActivityOpen: (String, String) -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var permissionRequested by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { it }
        locationProvider.checkPermission()
        if (granted) {
            locationProvider.requestLocation()
            locationProvider.startTracking()
        }
    }

    LaunchedEffect(Unit) {
        locationProvider.checkPermission()
        if (!locationProvider.hasPermission && !permissionRequested) {
            permissionRequested = true
            permissionLauncher.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            )
        } else if (locationProvider.hasPermission) {
            locationProvider.requestLocation()
            locationProvider.startTracking()
        }
    }

    LaunchedEffect(locationProvider.hasPermission) {
        if (locationProvider.hasPermission) {
            locationProvider.requestLocation()
            locationProvider.startTracking()
        }
    }

    DisposableEffect(Unit) {
        onDispose { locationProvider.stopTracking() }
    }

    val userCoord = locationProvider.latitude?.let { lat ->
        locationProvider.longitude?.let { lon -> MapCoordinate(lat, lon) }
    }
    val avatarSize = if (LocalConfiguration.current.screenWidthDp >= 600) 56 else 52

    Box(modifier = Modifier.fillMaxSize()) {
        MapLibreMapView(
            modifier = Modifier.fillMaxSize(),
            styleJson = mapViewModel.mapStyleJson,
            activities = mapViewModel.visibleActivities,
            userCoordinate = userCoord,
            selectedActivityId = mapViewModel.selectedActivity?.id,
            initialCamera = mapViewModel.initialCamera,
            onViewportIdle = { viewport -> mapViewModel.mapBecameIdle(viewport) },
            onActivityTap = { id -> mapViewModel.selectActivity(id) },
            onMapTap = { mapViewModel.clearSelection() }
        )

        if (!android.os.Build.SUPPORTED_ABIS.any { it.contains("x86") } && mapViewModel.mapStyleJson == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Surface(
                    shape = RoundedCornerShape(22.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                    shadowElevation = 10.dp
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (mapViewModel.mapStyleLoading) {
                            CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 3.dp)
                            Text("Загружаем карту")
                        } else {
                            Icon(Icons.Default.CloudOff, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                            Text(mapViewModel.mapStyleError ?: "Карта временно недоступна")
                            TextButton(onClick = mapViewModel::reloadMapStyle) { Text("Повторить") }
                        }
                    }
                }
            }
        } else when (mapViewModel.state) {
            frezzy.gonow.models.MapContentState.Initial,
            frezzy.gonow.models.MapContentState.Loading -> if (!android.os.Build.SUPPORTED_ABIS.any { it.contains("x86") }) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center).size(32.dp),
                    strokeWidth = 3.dp
                )
            }
            frezzy.gonow.models.MapContentState.Failed -> {
                Surface(
                    modifier = Modifier.align(Alignment.Center),
                    shape = RoundedCornerShape(18.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                    shadowElevation = 8.dp
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.CloudOff, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Text("Не удалось обновить активности")
                        TextButton(onClick = mapViewModel::reload) { Text("Повторить") }
                    }
                }
            }
            else -> Unit
        }

        // Top row: weather widget (left) + avatar menu (right)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .statusBarsPadding(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            MapWeatherWidget(
                weatherViewModel = weatherViewModel,
                locationProvider = locationProvider,
                profileLatitude = user?.latitude,
                profileLongitude = user?.longitude,
                settingsPrefs = settingsPrefs
            )

            Box {
                Box(
                    modifier = Modifier
                        .size(avatarSize.dp)
                        .clip(CircleShape)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) { showMenu = true }
                ) {
                    ProfileAvatar(
                        avatarBytes = avatarBytes,
                        initials = user?.initials ?: "G",
                        size = avatarSize - 4
                    )
                }

                if (notificationUnreadCount > 0) {
                    Surface(
                        onClick = onNotificationsTap,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 5.dp, y = 2.dp)
                            .height(24.dp)
                            .defaultMinSize(minWidth = 40.dp),
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                        shadowElevation = 1.dp
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(Icons.Filled.Notifications, contentDescription = "Непрочитанные уведомления", modifier = Modifier.size(12.dp))
                            Text(notificationUnreadCount.coerceAtMost(99).let { if (it == 99) "99+" else it.toString() }, fontSize = 11.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
                        }
                    }
                } else {
                    val status = user?.profileStatus
                    if (status != null && status != ProfileStatus.COMPLETE) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(18.dp)
                            .clip(CircleShape)
                            .background(ProfileStatusColor[status.name] ?: Color.Transparent)
                            .padding(3.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Filled.Warning, contentDescription = null, tint = Color.White, modifier = Modifier.size(10.dp))
                    }
                    }
                }

                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    DropdownMenuItem(
                        text = { Text("Профиль") },
                        leadingIcon = { Icon(Icons.Filled.Person, contentDescription = null) },
                        onClick = { showMenu = false; onNavigateToProfile() }
                    )
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (notificationUnreadCount > 0) "Уведомления ($notificationUnreadCount)"
                                else "Уведомления"
                            )
                        },
                        leadingIcon = { Icon(Icons.Filled.Notifications, contentDescription = null) },
                        onClick = { showMenu = false; onNotificationsTap() }
                    )
                }
            }
        }

        // Activity card at bottom when selected
        mapViewModel.selectedActivity?.let { activity ->
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 20.dp, vertical = 12.dp)
                    .padding(bottom = 72.dp)
            ) {
                ActivityMapCard(
                    activity = activity,
                    onClose = { mapViewModel.clearSelection() },
                    onOpen = { onActivityOpen(activity.id, activity.title) }
                )
            }
        }

        // Filter button (bottom-right)
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 20.dp, bottom = 140.dp)
        ) {
            val activeCount = mapViewModel.filters.activeCount
            FloatingActionButton(
                onClick = { showFilterSheet = true },
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = if (activeCount > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                shape = CircleShape,
                modifier = Modifier.size(48.dp)
            ) {
                BadgedBox(badge = {
                    if (activeCount > 0) {
                        Badge { Text("$activeCount") }
                    }
                }) {
                    Icon(Icons.Filled.FilterList, contentDescription = "Фильтры")
                }
            }
        }

        // Search button (bottom-right, above filter)
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 20.dp, bottom = 200.dp)
        ) {
            FloatingActionButton(
                onClick = { showSearch = !showSearch },
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                shape = CircleShape,
                modifier = Modifier.size(48.dp)
            ) {
                Icon(Icons.Filled.Search, contentDescription = "Поиск")
            }
        }

        if (showSearch) {
            OutlinedTextField(
                value = mapViewModel.searchQuery,
                onValueChange = mapViewModel::updateSearchQuery,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).statusBarsPadding().padding(top = 72.dp),
                placeholder = { Text("Поиск активностей") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    IconButton(onClick = { mapViewModel.updateSearchQuery(""); showSearch = false }) {
                        Icon(Icons.Default.Close, contentDescription = "Закрыть поиск")
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(18.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surface,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    }

    if (showFilterSheet) {
        MapFilterSheet(
            currentFilters = mapViewModel.filters,
            onApply = { newFilters -> mapViewModel.applyFilters(newFilters) },
            onDismiss = { showFilterSheet = false }
        )
    }
}
