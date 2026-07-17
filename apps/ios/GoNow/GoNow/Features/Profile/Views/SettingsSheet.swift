import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        GlassCard(style: .prominent) {
                            ThemeSelector()
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Label("Погода", systemImage: "cloud.sun.fill")
                                    .font(AppTypography.sectionTitle)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Единицы температуры для виджета на карте.")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                Picker("Температура", selection: $temperatureUnit) {
                                    ForEach(TemperatureUnit.allCases) { unit in
                                        Text(unit.title).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityHint("Авто использует региональные настройки устройства")
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Label("Аккаунт", systemImage: "person.crop.circle")
                                    .font(AppTypography.sectionTitle)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Выход завершит сессию только на этом устройстве.")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                Button {
                                    Task {
                                        await appState.logout()
                                        dismiss()
                                    }
                                } label: {
                                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                                .buttonStyle(GlassSecondaryButtonStyle(isDestructive: true))
                                .padding(.top, AppSpacing.xs)
                            }
                        }
                    }
                    .frame(maxWidth: AppLayout.maxContentWidth)
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.vertical, AppSpacing.xl)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(AppColors.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
struct DesignSystemPreview: View {
    @StateObject private var themeManager = ThemeManager()

    var body: some View {
        GlassScreen {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ThemeSelector()
                GlassCard {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Заголовок карточки")
                            .font(AppTypography.cardTitle)
                        Text("Поверхности, типографика и контраст автоматически адаптируются к светлой и тёмной теме.")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Button("Основное действие") {}
                    .buttonStyle(GradientPrimaryButtonStyle())
                Button("Второстепенное действие") {}
                    .buttonStyle(GlassSecondaryButtonStyle())
                AppTextField(title: "Пример поля", text: .constant(""), prompt: "Введите текст")
                AppEmptyState(symbol: "sparkles", title: "Пока пусто", message: "Компонент пустого состояния для будущих экранов.")
            }
        }
        .environmentObject(themeManager)
    }
}
#endif

#if DEBUG
#Preview("Компоненты · светлая") {
    DesignSystemPreview()
        .preferredColorScheme(.light)
}

#Preview("Компоненты · тёмная") {
    DesignSystemPreview()
        .preferredColorScheme(.dark)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
#endif
