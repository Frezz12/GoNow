package frezzy.gonow

import android.app.Application
import android.util.Log
import coil.ImageLoader
import coil.ImageLoaderFactory
import frezzy.gonow.core.AppContainer

class GoNowApp : Application(), ImageLoaderFactory {
    val container: AppContainer by lazy { AppContainer(this) }

    override fun onCreate() {
        super.onCreate()
        container
        container.settingsPrefs.applyLanguage()
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

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .okHttpClient(container.apiClient.okHttpClient)
        .crossfade(true)
        .build()
}
