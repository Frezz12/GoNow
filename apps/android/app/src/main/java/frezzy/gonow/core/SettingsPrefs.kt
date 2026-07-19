package frezzy.gonow.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf

class SettingsPrefs(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("gonow_settings", Context.MODE_PRIVATE)

    var themeMode = mutableStateOf(prefs.getInt(KEY_THEME, THEME_LIGHT))
        private set

    var temperatureUnit = mutableStateOf(prefs.getInt(KEY_TEMP_UNIT, TEMP_AUTO))
        private set

    var useProfileLocation = mutableStateOf(prefs.getBoolean(KEY_USE_PROFILE_LOCATION, false))
        private set

    fun setThemeMode(value: Int) {
        themeMode.value = value
        prefs.edit().putInt(KEY_THEME, value).apply()
    }

    fun setTemperatureUnit(value: Int) {
        temperatureUnit.value = value
        prefs.edit().putInt(KEY_TEMP_UNIT, value).apply()
    }

    fun setUseProfileLocation(value: Boolean) {
        useProfileLocation.value = value
        prefs.edit().putBoolean(KEY_USE_PROFILE_LOCATION, value).apply()
    }

    companion object {
        const val THEME_SYSTEM = 0
        const val THEME_LIGHT = 1
        const val THEME_DARK = 2

        const val TEMP_AUTO = 0
        const val TEMP_CELSIUS = 1
        const val TEMP_FAHRENHEIT = 2

        private const val KEY_THEME = "theme_mode"
        private const val KEY_TEMP_UNIT = "temperature_unit"
        private const val KEY_USE_PROFILE_LOCATION = "use_profile_location"

        @Volatile
        private var INSTANCE: SettingsPrefs? = null

        fun getInstance(context: Context): SettingsPrefs {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SettingsPrefs(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
}
