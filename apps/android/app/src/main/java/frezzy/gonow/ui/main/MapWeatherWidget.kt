package frezzy.gonow.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.TemperatureUnit
import frezzy.gonow.core.weather.WeatherViewModel

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
        SettingsPrefs.TEMP_FAHRENHEIT -> TemperatureUnit.FAHRENHEIT
        SettingsPrefs.TEMP_CELSIUS -> TemperatureUnit.CELSIUS
        else -> TemperatureUnit.CELSIUS
    }

    val latitude = locationProvider.latitude ?: profileLatitude
    val longitude = locationProvider.longitude ?: profileLongitude

    LaunchedEffect(latitude, longitude, tempUnitValue) {
        if (latitude != null && longitude != null) {
            weatherViewModel.refresh(latitude, longitude, unit)
        }
    }

    val shape = RoundedCornerShape(14.dp)

    Row(
        modifier = Modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        val snapshot = weatherViewModel.snapshot

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
                fontSize = 15.sp
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
                latitude == null -> "Нет координат"
                weatherViewModel.unavailableReason != null -> "Нет сети"
                else -> "Погода"
            }
            Text(text = text, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Medium, fontSize = 13.sp)
        }
    }
}
