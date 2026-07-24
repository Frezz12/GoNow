package frezzy.gonow.data

import android.content.Context
import frezzy.gonow.models.MapCoordinate
import frezzy.gonow.models.MapViewport
import frezzy.gonow.models.PersistedMapCamera

class MapCameraStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gonow_map_camera", Context.MODE_PRIVATE)

    fun load(): PersistedMapCamera? {
        if (!prefs.contains(KEY_LATITUDE)) return null
        return PersistedMapCamera(
            center = MapCoordinate(
                prefs.getString(KEY_LATITUDE, null)?.toDoubleOrNull() ?: return null,
                prefs.getString(KEY_LONGITUDE, null)?.toDoubleOrNull() ?: return null
            ),
            zoom = prefs.getString(KEY_ZOOM, null)?.toDoubleOrNull() ?: 11.0
        )
    }

    fun save(viewport: MapViewport) {
        prefs.edit()
            .putString(KEY_LATITUDE, viewport.center.latitude.toString())
            .putString(KEY_LONGITUDE, viewport.center.longitude.toString())
            .putString(KEY_ZOOM, viewport.zoom.toString())
            .apply()
    }

    private companion object {
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_ZOOM = "zoom"
    }
}
