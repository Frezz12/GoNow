import SwiftUI
import Combine

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.string("settings.theme.system")
        case .light: L10n.string("settings.theme.light")
        case .dark: L10n.string("settings.theme.dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @AppStorage(AppTheme.appStorageKey) private var storedMode: ThemeMode = .system

    var mode: ThemeMode { storedMode }

    var preferredColorScheme: ColorScheme? {
        switch storedMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func select(_ mode: ThemeMode) {
        guard storedMode != mode else { return }
        objectWillChange.send()
        storedMode = mode
        AppHaptics.selection()
    }
}

struct ThemeSelector: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("settings.theme.title")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("settings.theme.description")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.xs) {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        themeManager.select(mode)
                    } label: {
                        VStack(spacing: AppSpacing.xs) {
                            Image(systemName: mode.symbol)
                                .font(.body.weight(.semibold))
                            Text(mode.title)
                                .font(AppTypography.captionStrong)
                                .lineLimit(1)
                        }
                        .foregroundStyle(themeManager.mode == mode ? AppColors.textOnAccent : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .fill(themeManager.mode == mode ? AnyShapeStyle(AppGradients.brand) : AnyShapeStyle(AppColors.surfaceSecondary))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(themeManager.mode == mode ? AppColors.glassBorder.opacity(0.65) : AppColors.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .accessibilityLabel(L10n.format("settings.theme.accessibility %@", mode.title))
                    .accessibilityAddTraits(themeManager.mode == mode ? .isSelected : [])
                }
            }
        }
    }
}
