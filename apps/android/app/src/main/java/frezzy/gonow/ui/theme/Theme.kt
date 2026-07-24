package frezzy.gonow.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import frezzy.gonow.core.SettingsPrefs

private val LightColors = lightColorScheme(
    primary = Color(0xFF7547E8),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE9DFFF),
    onPrimaryContainer = Color(0xFF2D1268),
    secondary = Color(0xFFE85CA8),
    secondaryContainer = Color(0xFFFFD8EC),
    onSecondaryContainer = Color(0xFF561039),
    background = Color(0xFFF6F5FA),
    onBackground = Color(0xFF181620),
    surface = Color.White,
    onSurface = Color(0xFF181620),
    surfaceVariant = Color(0xFFEFEDF5),
    onSurfaceVariant = Color(0xFF686374),
    error = Color(0xFFD9475B),
    outline = Color(0xFFCFC4F2)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8B5CF6),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF392366),
    onPrimaryContainer = Color(0xFFEADDFF),
    secondary = Color(0xFFF472B6),
    secondaryContainer = Color(0xFF5A2343),
    onSecondaryContainer = Color(0xFFFFD8EA),
    background = Color(0xFF0B0B14),
    onBackground = Color(0xFFF7F5FF),
    surface = Color(0xFF171624),
    onSurface = Color(0xFFF7F5FF),
    surfaceVariant = Color(0xFF1E1C2D),
    onSurfaceVariant = Color(0xFFB8B4C8),
    error = Color(0xFFFF667A),
    outline = Color(0xFF3D3852)
)

@Composable
fun GoNowTheme(
    settingsPrefs: SettingsPrefs,
    content: @Composable () -> Unit
) {
    val themeMode = settingsPrefs.themeMode.value

    val isDark = when (themeMode) {
        SettingsPrefs.THEME_DARK -> true
        SettingsPrefs.THEME_LIGHT -> false
        else -> isSystemInDarkTheme()
    }

    val colorScheme = if (isDark) DarkColors else LightColors
    val view = LocalView.current

    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.background.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !isDark
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
