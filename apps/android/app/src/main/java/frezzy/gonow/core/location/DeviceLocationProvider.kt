package frezzy.gonow.core.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

class DeviceLocationProvider(private val context: Context) {

    private val fusedClient: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)

    var latitude by mutableStateOf<Double?>(null)
        private set

    var longitude by mutableStateOf<Double?>(null)
        private set

    var isRequesting by mutableStateOf(false)
        private set

    var hasPermission by mutableStateOf(false)
        private set

    var error by mutableStateOf<String?>(null)
        private set

    private var locationCallback: LocationCallback? = null
    private var isTracking = false

    fun checkPermission() {
        hasPermission = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    fun requestLocation() {
        error = null
        if (!hasPermission) {
            error = "Нет разрешения на геолокацию"
            return
        }

        isRequesting = true

        try {
            fusedClient.lastLocation.addOnSuccessListener { location ->
                if (location != null) {
                    latitude = location.latitude
                    longitude = location.longitude
                    isRequesting = false
                } else {
                    requestFreshLocation()
                }
            }.addOnFailureListener {
                isRequesting = false
                error = "Не удалось определить местоположение"
            }
        } catch (_: SecurityException) {
            isRequesting = false
            error = "Нет разрешения на геолокацию"
        }
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        if (isTracking || !hasPermission) return
        isTracking = true

        val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 10_000L)
            .setMinUpdateDistanceMeters(1000f)
            .setMinUpdateIntervalMillis(10_000L)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val location = result.lastLocation ?: return
                latitude = location.latitude
                longitude = location.longitude
            }
        }

        try {
            fusedClient.requestLocationUpdates(request, locationCallback!!, Looper.getMainLooper())
        } catch (_: SecurityException) {
            isTracking = false
        }
    }

    fun stopTracking() {
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        locationCallback = null
        isTracking = false
    }

    @SuppressLint("MissingPermission")
    private fun requestFreshLocation() {
        val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 0)
            .setMaxUpdates(1)
            .setDurationMillis(10_000)
            .build()

        try {
            fusedClient.requestLocationUpdates(request, object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    val location = result.lastLocation
                    if (location != null) {
                        latitude = location.latitude
                        longitude = location.longitude
                    }
                    isRequesting = false
                    fusedClient.removeLocationUpdates(this)
                }
            }, Looper.getMainLooper())
        } catch (_: SecurityException) {
            isRequesting = false
            error = "Нет разрешения на геолокацию"
        }
    }
}
