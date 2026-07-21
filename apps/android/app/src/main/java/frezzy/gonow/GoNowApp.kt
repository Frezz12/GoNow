package frezzy.gonow

import android.app.Application
import android.util.Log

class GoNowApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            val mapLibreClass = Class.forName("org.maplibre.android.MapLibre")
            val wktClass = Class.forName("org.maplibre.android.WellKnownTileServer")
            val mapbox = wktClass.getField("Mapbox").get(null)
            mapLibreClass.getMethod(
                "getInstance",
                android.content.Context::class.java,
                String::class.java,
                wktClass
            ).invoke(null, this, "", mapbox)
        } catch (e: Exception) {
            Log.w("GoNowApp", "MapLibre init failed", e)
        }
    }
}
