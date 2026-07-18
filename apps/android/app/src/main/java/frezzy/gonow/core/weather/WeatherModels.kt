package frezzy.gonow.core.weather

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
import kotlin.math.roundToInt
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class TemperatureUnit(val apiValue: String, val label: String) {
    CELSIUS("celsius", "°C"),
    FAHRENHEIT("fahrenheit", "°F");

    companion object {
        fun effective(unit: TemperatureUnit): TemperatureUnit {
            val locale = java.util.Locale.getDefault()
            val country = locale.country.uppercase()
            return if (country == "US") FAHRENHEIT else CELSIUS
        }
    }
}

data class WeatherSnapshot(
    val temperature: Double,
    val unit: TemperatureUnit,
    val condition: WeatherCondition
) {
    val temperatureText: String
        get() = "${temperature.roundToInt()}°${if (unit == TemperatureUnit.CELSIUS) "C" else "F"}"
}

enum class WeatherCondition(val title: String, val icon: ImageVector) {
    CLEAR_DAY("Солнечно", Icons.Filled.WbSunny),
    CLEAR_NIGHT("Ясно", Icons.Filled.NightlightRound),
    PARTLY_CLOUDY_DAY("Облачно", Icons.Filled.WbCloudy),
    PARTLY_CLOUDY_NIGHT("Облачно", Icons.Filled.WbCloudy),
    CLOUDY("Пасмурно", Icons.Filled.Cloud),
    FOG("Туман", Icons.Filled.Cloud),
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

        fun fromMetSymbolCode(symbolCode: String): WeatherCondition {
            val isDay = !symbolCode.contains("night")
            return when {
                symbolCode.contains("thunder") -> THUNDERSTORM
                symbolCode.contains("snow") -> SNOW
                symbolCode.contains("rain") || symbolCode.contains("sleet") -> RAIN
                symbolCode.contains("fog") -> FOG
                symbolCode.contains("partlycloudy") || symbolCode.contains("fair") ->
                    if (isDay) PARTLY_CLOUDY_DAY else PARTLY_CLOUDY_NIGHT
                symbolCode.contains("clearsky") -> if (isDay) CLEAR_DAY else CLEAR_NIGHT
                else -> CLOUDY
            }
        }
    }
}

// --- API response models ---

@Serializable
data class GoNowWeatherResponse(
    @SerialName("data") val data: GoNowWeatherData
)

@Serializable
data class GoNowWeatherData(
    @SerialName("temperature") val temperature: Double,
    @SerialName("weatherCode") val weatherCode: Int,
    @SerialName("isDay") val isDay: Boolean,
    @SerialName("unit") val unit: String = "celsius"
)

@Serializable
data class OpenMeteoResponse(
    @SerialName("current") val current: OpenMeteoCurrent
)

@Serializable
data class OpenMeteoCurrent(
    @SerialName("temperature_2m") val temperature: Double,
    @SerialName("weather_code") val weatherCode: Int,
    @SerialName("is_day") val isDay: Int
)

@Serializable
data class MetNorwayResponse(
    @SerialName("properties") val properties: MetProperties
)

@Serializable
data class MetProperties(
    @SerialName("timeseries") val timeSeries: List<MetTimeSeries>
)

@Serializable
data class MetTimeSeries(
    @SerialName("data") val data: MetDataPoint
)

@Serializable
data class MetDataPoint(
    @SerialName("instant") val instant: MetInstant,
    @SerialName("next_1_hours") val nextOneHour: MetForecast? = null,
    @SerialName("next_6_hours") val nextSixHours: MetForecast? = null,
    @SerialName("next_12_hours") val nextTwelveHours: MetForecast? = null
)

@Serializable
data class MetInstant(
    @SerialName("details") val details: MetDetails
)

@Serializable
data class MetDetails(
    @SerialName("air_temperature") val airTemperature: Double
)

@Serializable
data class MetForecast(
    @SerialName("summary") val summary: MetSummary
)

@Serializable
data class MetSummary(
    @SerialName("symbol_code") val symbolCode: String
)
