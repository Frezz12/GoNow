package frezzy.gonow.core.weather

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

enum class TemperatureUnit(val apiValue: String, val label: String) {
    AUTOMATIC("auto", "Авто"),
    CELSIUS("celsius", "°C"),
    FAHRENHEIT("fahrenheit", "°F");

    companion object {
        fun effective(unit: TemperatureUnit): TemperatureUnit {
            if (unit != AUTOMATIC) return unit
            val locale = java.util.Locale.getDefault()
            val country = locale.country.uppercase()
            return if (country == "US") FAHRENHEIT else CELSIUS
        }
    }
}

data class WeatherSnapshot(
    val city: String?,
    val temperature: Double,
    val apparentTemperature: Double,
    val humidity: Double,
    val windSpeed: Double,
    val unit: TemperatureUnit,
    val condition: WeatherCondition,
    val isDay: Boolean
) {
    val temperatureText: String
        get() = "${temperature.roundToInt()}°${if (unit == TemperatureUnit.FAHRENHEIT) "F" else ""}"

    val temperatureDetailText: String
        get() = "${temperature.roundToInt()}°${if (unit == TemperatureUnit.FAHRENHEIT) "F" else "C"}"

    val apparentTemperatureText: String
        get() = "${apparentTemperature.roundToInt()}°${if (unit == TemperatureUnit.FAHRENHEIT) "F" else "C"}"

    val humidityText: String
        get() = "${humidity.roundToInt()}%"

    val windSpeedText: String
        get() = "${windSpeed.roundToInt()} км/ч"
}

enum class WeatherCondition(val title: String, val icon: ImageVector) {
    CLEAR_DAY("Солнечно", Icons.Filled.WbSunny),
    CLEAR_NIGHT("Ясно", Icons.Filled.NightlightRound),
    PARTLY_CLOUDY_DAY("Переменная облачность", Icons.Filled.WbCloudy),
    PARTLY_CLOUDY_NIGHT("Переменная облачность", Icons.Filled.NightlightRound),
    CLOUDY("Пасмурно", Icons.Filled.Cloud),
    FOG("Туман", Icons.Filled.WbCloudy),
    DRIZZLE("Морось", Icons.Filled.Grain),
    RAIN("Дождь", Icons.Filled.Umbrella),
    SNOW("Снег", Icons.Filled.AcUnit),
    THUNDERSTORM("Гроза", Icons.Filled.Thunderstorm);

    companion object {
        fun fromWeatherCode(code: Int, isDay: Boolean): WeatherCondition = when (code) {
            0 -> if (isDay) CLEAR_DAY else CLEAR_NIGHT
            1, 2 -> if (isDay) PARTLY_CLOUDY_DAY else PARTLY_CLOUDY_NIGHT
            3 -> CLOUDY
            45, 48 -> FOG
            in 51..57 -> DRIZZLE
            in 61..67, in 80..82 -> RAIN
            in 71..77, in 85..86 -> SNOW
            else -> THUNDERSTORM
        }
    }
}

// --- API response models (GoNow backend only) ---

@Serializable
data class GoNowWeatherResponse(
    @SerialName("data") val data: WeatherDto
)

@Serializable
data class WeatherDto(
    @SerialName("city") val city: String? = null,
    @SerialName("temperature") val temperature: Double,
    @SerialName("apparentTemperature") val apparentTemperature: Double,
    @SerialName("relativeHumidity") val relativeHumidity: Double,
    @SerialName("windSpeed") val windSpeed: Double,
    @SerialName("unit") val unit: String,
    @SerialName("weatherCode") val weatherCode: Int,
    @SerialName("isDay") val isDay: Boolean
)
