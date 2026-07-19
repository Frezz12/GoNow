package frezzy.gonow.core.weather

import android.util.Log
import frezzy.gonow.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Locale
import java.util.concurrent.TimeUnit

private const val TAG = "WeatherRepo"

class WeatherRepository {

    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    suspend fun fetch(
        latitude: Double,
        longitude: Double,
        unit: TemperatureUnit,
        locale: String = resolveLocale()
    ): WeatherSnapshot = withContext(Dispatchers.IO) {
        val effectiveUnit = TemperatureUnit.effective(unit)
        val url = "${BuildConfig.API_BASE_URL}/weather/current" +
            "?latitude=$latitude&longitude=$longitude" +
            "&unit=${effectiveUnit.apiValue}&locale=$locale"
        Log.d(TAG, "Fetching weather: $url")
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .build()
        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: ""
        Log.d(TAG, "Response ${response.code}: $body")
        if (!response.isSuccessful) throw WeatherException(response.code, "HTTP ${response.code}")
        if (body.isBlank()) throw WeatherException(-1, "Empty body")
        val parsed = json.decodeFromString<GoNowWeatherResponse>(body)
        val data = parsed.data
        WeatherSnapshot(
            city = data.city,
            temperature = data.temperature,
            apparentTemperature = data.apparentTemperature,
            humidity = data.relativeHumidity,
            windSpeed = data.windSpeed,
            unit = effectiveUnit,
            condition = WeatherCondition.fromWeatherCode(data.weatherCode, data.isDay),
            isDay = data.isDay
        )
    }

    private fun resolveLocale(): String {
        val lang = Locale.getDefault().language
        val country = Locale.getDefault().country.uppercase()
        return when {
            lang == "zh" -> "zh-Hans"
            lang == "pt" && country == "BR" -> "pt-BR"
            lang == "en" && country == "US" -> "en-US"
            lang == "ru" -> "ru"
            lang == "de" -> "de"
            lang == "fr" -> "fr"
            lang == "es" -> "es"
            lang == "en" -> "en"
            else -> "en"
        }
    }
}

class WeatherException(val httpCode: Int, message: String) : Exception(message)
