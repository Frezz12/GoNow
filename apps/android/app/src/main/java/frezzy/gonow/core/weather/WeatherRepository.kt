package frezzy.gonow.core.weather

import frezzy.gonow.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class WeatherRepository {

    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    suspend fun fetch(latitude: Double, longitude: Double, unit: TemperatureUnit): WeatherSnapshot {
        return withContext(Dispatchers.IO) {
            try {
                fetchViaGoNowBackend(latitude, longitude, unit)
            } catch (_: Exception) {
                try {
                    fetchOpenMeteo(latitude, longitude, unit)
                } catch (_: Exception) {
                    fetchMetNorway(latitude, longitude, unit)
                }
            }
        }
    }

    private fun fetchViaGoNowBackend(latitude: Double, longitude: Double, unit: TemperatureUnit): WeatherSnapshot {
        val url = "${BuildConfig.API_BASE_URL}/weather/current?latitude=$latitude&longitude=$longitude&unit=${unit.apiValue}"
        val request = Request.Builder().url(url).header("Accept", "application/json").build()
        val response = client.newCall(request).execute()
        if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
        val body = response.body?.string() ?: throw Exception("Empty body")
        val parsed = json.decodeFromString<GoNowWeatherResponse>(body)
        return WeatherSnapshot(
            temperature = parsed.data.temperature,
            unit = unit,
            condition = WeatherCondition.fromWeatherCode(parsed.data.weatherCode, parsed.data.isDay)
        )
    }

    private fun fetchOpenMeteo(latitude: Double, longitude: Double, unit: TemperatureUnit): WeatherSnapshot {
        val url = "https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude" +
            "&current=temperature_2m,weather_code,is_day&temperature_unit=${unit.apiValue}&forecast_days=1"
        val request = Request.Builder().url(url).build()
        val response = client.newCall(request).execute()
        if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
        val body = response.body?.string() ?: throw Exception("Empty body")
        val parsed = json.decodeFromString<OpenMeteoResponse>(body)
        return WeatherSnapshot(
            temperature = parsed.current.temperature,
            unit = unit,
            condition = WeatherCondition.fromWeatherCode(parsed.current.weatherCode, parsed.current.isDay == 1)
        )
    }

    private fun fetchMetNorway(latitude: Double, longitude: Double, unit: TemperatureUnit): WeatherSnapshot {
        val url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=$latitude&lon=$longitude"
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "GoNow/1.0 (https://github.com/Frezz12/GoNow)")
            .build()
        val response = client.newCall(request).execute()
        if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
        val body = response.body?.string() ?: throw Exception("Empty body")
        val parsed = json.decodeFromString<MetNorwayResponse>(body)
        val current = parsed.properties.timeSeries.firstOrNull() ?: throw Exception("No data")
        val celsius = current.data.instant.details.airTemperature
        val temperature = if (unit == TemperatureUnit.FAHRENHEIT) (celsius * 9 / 5) + 32 else celsius
        val symbolCode = current.data.nextOneHour?.summary?.symbolCode
            ?: current.data.nextSixHours?.summary?.symbolCode
            ?: current.data.nextTwelveHours?.summary?.symbolCode
            ?: "cloudy"
        return WeatherSnapshot(
            temperature = temperature,
            unit = unit,
            condition = WeatherCondition.fromMetSymbolCode(symbolCode)
        )
    }
}
