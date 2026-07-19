package frezzy.gonow.core.weather

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kotlin.math.abs

class WeatherViewModel : ViewModel() {

    private val repository = WeatherRepository()

    var snapshot by mutableStateOf<WeatherSnapshot?>(null)
        private set

    var isLoading by mutableStateOf(false)
        private set

    var unavailableReason by mutableStateOf<WeatherUnavailableReason?>(null)
        private set

    private var lastLat: Double? = null
    private var lastLon: Double? = null
    private var lastLocale: String? = null
    private var lastUnit: String? = null
    private var lastRequestTime = 0L

    fun refresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit, locale: String) {
        if (latitude == null || longitude == null) {
            snapshot = null
            unavailableReason = WeatherUnavailableReason.LOCATION_UNAVAILABLE
            return
        }

        val effectiveUnit = TemperatureUnit.effective(unit)
        val now = System.currentTimeMillis()

        // Skip if coords, locale, and unit barely changed and last response < 10 min ago
        val latDiff = lastLat?.let { abs(latitude - it) } ?: Double.MAX_VALUE
        val lonDiff = lastLon?.let { abs(longitude - it) } ?: Double.MAX_VALUE
        if (latDiff < 0.001 && lonDiff < 0.001
            && locale == lastLocale
            && effectiveUnit.apiValue == lastUnit
            && now - lastRequestTime < 600_000) return

        viewModelScope.launch {
            isLoading = true
            unavailableReason = null
            try {
                snapshot = repository.fetch(latitude, longitude, effectiveUnit, locale)
                lastLat = latitude
                lastLon = longitude
                lastLocale = locale
                lastUnit = effectiveUnit.apiValue
                lastRequestTime = now
            } catch (e: Exception) {
                snapshot = null
                unavailableReason = when {
                    e is WeatherException && e.httpCode == 503 -> WeatherUnavailableReason.SERVICE
                    e.message?.contains("timeout", true) == true -> WeatherUnavailableReason.NETWORK
                    e.message?.contains("connect", true) == true -> WeatherUnavailableReason.NETWORK
                    else -> WeatherUnavailableReason.NETWORK
                }
            } finally {
                isLoading = false
            }
        }
    }

    fun forceRefresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit, locale: String) {
        lastRequestTime = 0L
        lastUnit = null
        lastLocale = null
        lastLat = null
        lastLon = null
        refresh(latitude, longitude, unit, locale)
    }

    fun reset() {
        snapshot = null
        unavailableReason = null
        lastLat = null
        lastLon = null
        lastLocale = null
        lastUnit = null
        lastRequestTime = 0L
    }
}

enum class WeatherUnavailableReason {
    LOCATION_UNAVAILABLE,
    NETWORK,
    SERVICE
}
