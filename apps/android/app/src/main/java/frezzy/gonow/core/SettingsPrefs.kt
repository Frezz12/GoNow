package frezzy.gonow.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

enum class AppLanguage(val tag: String?, val displayName: String) {
    SYSTEM(null, "Системный"),
    RUSSIAN("ru", "Русский"),
    ENGLISH("en", "English"),
    ENGLISH_US("en-US", "English (United States)"),
    GERMAN("de", "Deutsch"),
    FRENCH("fr", "Français"),
    SPANISH("es", "Español"),
    PORTUGUESE_BRAZIL("pt-BR", "Português (Brasil)"),
    CHINESE_SIMPLIFIED("zh-Hans", "简体中文");

    companion object {
        fun fromTag(tag: String?): AppLanguage {
            if (tag == null) return SYSTEM
            return entries.firstOrNull { it.tag.equals(tag, ignoreCase = true) } ?: ENGLISH
        }
    }
}

class SettingsPrefs(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("gonow_settings", Context.MODE_PRIVATE)

    var themeMode = mutableStateOf(prefs.getInt(KEY_THEME, THEME_LIGHT))
        private set

    var temperatureUnit = mutableStateOf(prefs.getInt(KEY_TEMP_UNIT, TEMP_AUTO))
        private set

    var useProfileLocation = mutableStateOf(prefs.getBoolean(KEY_USE_PROFILE_LOCATION, true))
        private set

    var language = mutableStateOf(AppLanguage.fromTag(prefs.getString(KEY_LANGUAGE, null)))
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

    fun setLanguage(value: AppLanguage) {
        language.value = value
        prefs.edit().putString(KEY_LANGUAGE, value.tag).apply()
        applyLanguage()
    }

    fun applyLanguage() {
        val locales = language.value.tag?.let(LocaleListCompat::forLanguageTags)
            ?: LocaleListCompat.getEmptyLocaleList()
        AppCompatDelegate.setApplicationLocales(locales)
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
        private const val KEY_LANGUAGE = "interface_language"

        @Volatile
        private var INSTANCE: SettingsPrefs? = null

        fun getInstance(context: Context): SettingsPrefs {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SettingsPrefs(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
}
