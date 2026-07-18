package frezzy.gonow.core.weather

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch

class WeatherViewModel : ViewModel() {

    private val repository = WeatherRepository()

    var snapshot by mutableStateOf<WeatherSnapshot?>(null)
        private set

    var isLoading by mutableStateOf(false)
        private set

    var unavailableReason by mutableStateOf<WeatherUnavailableReason?>(null)
        private set

    private var lastRequest: Triple<Double, Double, TemperatureUnit>? = null
    private var lastRequestTime = 0L

    fun refresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit) {
        if (latitude == null || longitude == null) {
            snapshot = null
            unavailableReason = WeatherUnavailableReason.LOCATION_UNAVAILABLE
            return
        }

        val effectiveUnit = TemperatureUnit.effective(unit)
        val key = Triple(latitude, longitude, effectiveUnit)
        val now = System.currentTimeMillis()

        if (lastRequest == key && now - lastRequestTime < 600_000) return

        viewModelScope.launch {
            isLoading = true
            unavailableReason = null
            try {
                snapshot = repository.fetch(latitude, longitude, effectiveUnit)
                lastRequest = key
                lastRequestTime = now
            } catch (e: Exception) {
                snapshot = null
                unavailableReason = when {
                    e.message?.contains("timeout", true) == true -> WeatherUnavailableReason.NETWORK
                    e.message?.contains("connect", true) == true -> WeatherUnavailableReason.NETWORK
                    else -> WeatherUnavailableReason.SERVICE
                }
            } finally {
                isLoading = false
            }
        }
    }
}

enum class WeatherUnavailableReason {
    LOCATION_UNAVAILABLE,
    NETWORK,
    SERVICE
}
