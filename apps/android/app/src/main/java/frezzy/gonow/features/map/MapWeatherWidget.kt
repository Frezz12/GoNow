package frezzy.gonow.features.map

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.TemperatureUnit
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.core.weather.WeatherUnavailableReason
import java.util.Locale

@Composable
fun MapWeatherWidget(
    weatherViewModel: WeatherViewModel,
    locationProvider: DeviceLocationProvider,
    profileLatitude: Double?,
    profileLongitude: Double?,
    settingsPrefs: SettingsPrefs
) {
    val tempUnitValue by settingsPrefs.temperatureUnit
    val unit = when (tempUnitValue) {
        SettingsPrefs.TEMP_CELSIUS -> TemperatureUnit.CELSIUS
        SettingsPrefs.TEMP_FAHRENHEIT -> TemperatureUnit.FAHRENHEIT
        else -> TemperatureUnit.AUTOMATIC
    }

    // Observe location state changes
    val gpsLat = locationProvider.latitude
    val gpsLon = locationProvider.longitude
    val useProfile by settingsPrefs.useProfileLocation

    val latitude = if (useProfile) profileLatitude else (gpsLat ?: profileLatitude)
    val longitude = if (useProfile) profileLongitude else (gpsLon ?: profileLongitude)

    // Determine reason why weather is unavailable
    val weatherUnavailableText = when {
        useProfile && profileLatitude == null && profileLongitude == null -> "Укажите координаты в профиле"
        !useProfile && gpsLat == null && profileLatitude == null -> "📍"
        else -> null
    }

    val locale = remember { "ru" }

    // Fetch weather when coords or unit change
    LaunchedEffect(latitude, longitude, tempUnitValue, locale, useProfile) {
        if (latitude != null && longitude != null) {
            weatherViewModel.forceRefresh(latitude, longitude, unit, locale)
        }
    }

    var expanded by remember { mutableStateOf(false) }
    val snapshot = weatherViewModel.snapshot
    val shape = RoundedCornerShape(16.dp)

    Card(
        shape = shape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
        modifier = Modifier
            .width(if (expanded) 260.dp else 96.dp)
            .clickable { expanded = !expanded }
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            // Collapsed: icon + temperature
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (snapshot != null) {
                    Icon(
                        imageVector = snapshot.condition.icon,
                        contentDescription = snapshot.condition.title,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(22.dp)
                    )
                    Text(
                        text = snapshot.temperatureText,
                        color = MaterialTheme.colorScheme.onSurface,
                        fontWeight = FontWeight.Medium,
                        fontSize = 16.sp,
                        maxLines = 1
                    )
                } else if (weatherViewModel.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Icon(Icons.Filled.Cloud, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                    val text = when {
                        latitude == null -> "📍"
                        weatherViewModel.unavailableReason == WeatherUnavailableReason.LOCATION_UNAVAILABLE -> "📍"
                        weatherViewModel.unavailableReason == WeatherUnavailableReason.NETWORK -> "Нет сети"
                        weatherViewModel.unavailableReason == WeatherUnavailableReason.SERVICE -> "Недоступно"
                        else -> "Погода"
                    }
                    Text(text = text, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Medium, fontSize = 13.sp)
                }
            }

            // Expanded details
            AnimatedVisibility(
                visible = expanded && snapshot != null,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Spacer(Modifier.height(4.dp))
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Spacer(Modifier.height(4.dp))

                    // City + temp detail
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = snapshot?.city ?: "Текущее местоположение",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = snapshot?.temperatureDetailText ?: "",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }

                    Text(
                        text = snapshot?.condition?.title ?: "",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    Spacer(Modifier.height(2.dp))

                    // Details row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        DetailItem(icon = Icons.Filled.Thermostat, label = snapshot?.apparentTemperatureText ?: "—")
                        DetailItem(icon = Icons.Filled.WaterDrop, label = snapshot?.humidityText ?: "—")
                        DetailItem(icon = Icons.Filled.Air, label = snapshot?.windSpeedText ?: "—")
                    }

                    Spacer(Modifier.height(2.dp))

                    Text(
                        text = "Данные места © OpenStreetMap contributors",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 9.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailItem(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
