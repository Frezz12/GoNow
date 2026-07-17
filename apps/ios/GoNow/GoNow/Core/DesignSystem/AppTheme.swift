import SwiftUI
import UIKit

/// Semantic, dynamic colors for all GoNow surfaces. Do not use raw RGB values in screens.
enum AppColors {
    static let backgroundPrimary = adaptive(light: 0xF6F5FA, dark: 0x0B0B14)
    static let backgroundSecondary = adaptive(light: 0xEFEDF5, dark: 0x11111C)
    static let surfacePrimary = adaptive(light: 0xFFFFFF, dark: 0x171624)
    static let surfaceSecondary = adaptive(light: 0xF8F7FC, dark: 0x1E1C2D)
    static let surfaceElevated = adaptive(light: 0xFFFFFF, dark: 0x252238)
    static let surfaceGlass = adaptive(light: 0xFDFBFF, dark: 0x1D1A2A)
    static let surfaceGlassStrong = adaptive(light: 0xF7F4FC, dark: 0x282339)

    static let textPrimary = adaptive(light: 0x181620, dark: 0xF7F5FF)
    static let textSecondary = adaptive(light: 0x686374, dark: 0xB8B4C8)
    static let textMuted = adaptive(light: 0x918B9C, dark: 0x777287)
    static let textOnAccent = Color.white

    static let borderSubtle = adaptive(light: 0xE3DFEA, dark: 0x322E40)
    static let borderStrong = adaptive(light: 0xD1C9E1, dark: 0x49425B)
    static let divider = adaptive(light: 0xE8E4EF, dark: 0x2E2A3A)

    static let accentPrimary = adaptive(light: 0x7547E8, dark: 0x8B5CF6)
    static let accentPrimarySoft = adaptive(light: 0x9365F4, dark: 0xA879FF)
    static let accentSecondary = adaptive(light: 0xE85CA8, dark: 0xF472B6)
    static let locationAccent = adaptive(light: 0x239DCC, dark: 0x53C7F0)

    static let success = adaptive(light: 0x229F72, dark: 0x43D69F)
    static let warning = adaptive(light: 0xC68D1B, dark: 0xF6C65B)
    static let error = adaptive(light: 0xD9475B, dark: 0xFF667A)
    static let info = locationAccent

    static let shadow = adaptive(light: 0x5B526E, dark: 0x000000)
    static let glassHighlight = Color.white
    static let glassBorder = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum AppGradients {
    static let brand = LinearGradient(
        colors: [Color(red: 0.486, green: 0.361, blue: 0.988), Color(red: 0.690, green: 0.361, blue: 0.961), Color(red: 0.957, green: 0.447, blue: 0.714)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let brandSoft = LinearGradient(
        colors: [AppColors.accentPrimary.opacity(0.20), AppColors.accentSecondary.opacity(0.16), AppColors.locationAccent.opacity(0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassHighlight = LinearGradient(
        colors: [AppColors.glassHighlight.opacity(0.52), AppColors.glassHighlight.opacity(0.10), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let mapGlow = RadialGradient(
        colors: [AppColors.accentPrimary.opacity(0.30), AppColors.accentSecondary.opacity(0.10), .clear],
        center: .center,
        startRadius: 0,
        endRadius: 230
    )

    static let avatarRing = AngularGradient(
        colors: [AppColors.accentPrimary, AppColors.accentSecondary, AppColors.locationAccent, AppColors.accentPrimary],
        center: .center
    )
}

enum AppTheme {
    static let appStorageKey = "gonow.theme.mode"
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
