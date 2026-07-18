package frezzy.gonow.core.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
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
            fusedClient.lastLocation.addOnSuccessListener { location: Location? ->
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
