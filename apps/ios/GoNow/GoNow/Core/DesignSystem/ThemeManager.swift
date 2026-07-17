import SwiftUI
import Combine

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
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
            Text("Оформление")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Системная тема автоматически повторяет настройки оформления iPhone.")
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
                    .accessibilityLabel("Тема: \(mode.title)")
                    .accessibilityAddTraits(themeManager.mode == mode ? .isSelected : [])
                }
            }
        }
    }
}
