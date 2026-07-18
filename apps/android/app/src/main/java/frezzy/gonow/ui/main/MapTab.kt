package frezzy.gonow.ui.main

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.models.ProfileStatus
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*

@Composable
fun MapTab(
    user: User?,
    avatarBytes: ByteArray?,
    onNavigateToProfile: () -> Unit,
    weatherViewModel: WeatherViewModel,
    locationProvider: DeviceLocationProvider,
    settingsPrefs: SettingsPrefs
) {
    var showMenu by remember { mutableStateOf(false) }
    val context = LocalContext.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { it }
        if (granted) {
            locationProvider.checkPermission()
            locationProvider.requestLocation()
        }
    }

    LaunchedEffect(Unit) {
        locationProvider.checkPermission()
        if (!locationProvider.hasPermission) {
            permissionLauncher.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            )
        } else {
            locationProvider.requestLocation()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MapPreviewSurface()

        // Top row: weather widget (left) + avatar menu (right)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .statusBarsPadding(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            // Weather widget
            MapWeatherWidget(
                weatherViewModel = weatherViewModel,
                locationProvider = locationProvider,
                profileLatitude = user?.latitude,
                profileLongitude = user?.longitude,
                settingsPrefs = settingsPrefs
            )

            // Avatar with menu
            Box {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) { showMenu = true }
                ) {
                    ProfileAvatar(
                        avatarBytes = avatarBytes,
                        initials = user?.initials ?: "G",
                        size = 44
                    )
                }

                val status = user?.profileStatus
                if (status != null && status != ProfileStatus.COMPLETE) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 0.dp, y = 0.dp)
                            .size(18.dp)
                            .clip(CircleShape)
                            .background(status.color)
                            .padding(3.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Filled.Warning, contentDescription = null, tint = Color.White, modifier = Modifier.size(10.dp))
                    }
                }

                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    DropdownMenuItem(
                        text = { Text("Профиль") },
                        leadingIcon = { Icon(Icons.Filled.Person, contentDescription = null) },
                        onClick = { showMenu = false; onNavigateToProfile() }
                    )
                    DropdownMenuItem(
                        text = { Text("Уведомления") },
                        leadingIcon = { Icon(Icons.Filled.Notifications, contentDescription = null) },
                        onClick = { showMenu = false }
                    )
                }
            }
        }
    }
}

@Composable
private fun MapPreviewSurface() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                androidx.compose.ui.graphics.Brush.verticalGradient(
                    colors = listOf(Color(0xFFEFEDF5), Color(0xFF1E1C2D))
                )
            )
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val river = androidx.compose.ui.graphics.Path().apply {
                moveTo(-20f, size.height * 0.72f)
                cubicTo(size.width * 0.28f, size.height * 0.94f, size.width * 0.68f, size.height * 0.12f, size.width + 30f, size.height * 0.30f)
            }
            drawPath(river, color = Color(0x9EFFFFFF), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 22f))

            listOf(0.16f, 0.34f, 0.56f, 0.78f).forEachIndexed { index, ratio ->
                val street = androidx.compose.ui.graphics.Path().apply {
                    moveTo(-20f, size.height * ratio)
                    val endY = size.height * (ratio + if (index % 2 == 0) 0.13f else -0.11f)
                    cubicTo(size.width * 0.30f, size.height * (ratio - 0.08f), size.width * 0.72f, size.height * (ratio + 0.08f), size.width + 20f, endY)
                }
                drawPath(street, color = Color(0xD1FFFFFF), style = androidx.compose.ui.graphics.drawscope.Stroke(width = if (index == 1) 11f else 7f))
            }

            listOf(0.19f, 0.47f, 0.73f, 0.91f).forEach { ratio ->
                val street = androidx.compose.ui.graphics.Path().apply {
                    moveTo(size.width * ratio, -20f)
                    lineTo(size.width * (ratio - 0.18f), size.height + 20f)
                }
                drawPath(street, color = Color(0xBDFFFFFF), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 6f))
            }
        }

        Box(
            modifier = Modifier
                .offset(x = (-22).dp, y = 126.dp)
                .size(140.dp, 90.dp)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(34.dp))
                .background(Color(0x38229F72))
        )
        Box(
            modifier = Modifier
                .offset(x = 200.dp, y = 400.dp)
                .size(160.dp, 80.dp)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(30.dp))
                .background(Color(0x29229F72))
        )
    }
}
