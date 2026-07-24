package frezzy.gonow.ui.theme

import androidx.compose.ui.graphics.Color

// Light theme (style.md)
val Primary = Color(0xFF7547E8)
val Accent = Color(0xFFE85CA8)
val Success = Color(0xFF229F72)
val Warning = Color(0xFFC68D1B)
val Danger = Color(0xFFD9475B)
val LocationAccent = Color(0xFF239DCC)
val FocusBlue = Color(0xFF637DF0)

val Background = Color(0xFFF6F5FA)
val BackgroundSecondary = Color(0xFFEFEDF5)
val SurfacePrimary = Color(0xFFFFFFFF)
val SurfaceSecondary = Color(0xFFF8F7FC)

val TextPrimary = Color(0xFF181620)
val TextSecondary = Color(0xFF686374)
val TextMuted = Color(0xFF918B9C)

val Border = Color(0xFFCFC4F2)

// Button gradient
val ButtonStart = Color(0xFF7C5CFC)
val ButtonMid = Color(0xFFB05CF5)
val ButtonEnd = Color(0xFFF472B6)

// Screen backdrop gradient
val BackdropTop = Color(0xFFFFDEE8)
val BackdropMid = Color(0xFFDBD6FA)
val BackdropBottom = Color(0xFFBADBFA)

// Glass (kept for compat but not used in new UI)
val GlassBackground = Color(0x0DFFFFFF)
val GlassBorder = Color(0x33FFFFFF)
val GlassBorderBottom = Color(0x337547E8)

// ProfileStatus colors (UI extension — kept out of domain model)
val ProfileStatusColor = mapOf(
    "COMPLETE" to Color.Transparent,
    "OPTIONAL" to Warning,
    "REQUIRED" to Danger
)
