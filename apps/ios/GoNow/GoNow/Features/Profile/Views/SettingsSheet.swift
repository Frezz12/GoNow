import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    GlassCard(style: .prominent) {
                        ThemeSelector()
                    }

                    GlassCard {
                        NavigationLink {
                            LanguageSettingsView()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "globe")
                                    .font(.title3)
                                    .foregroundStyle(AppColors.accentPrimary)
                                    .frame(width: AppLayout.minimumTouchTarget, height: AppLayout.minimumTouchTarget)
                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text("settings.language.title")
                                        .font(AppTypography.sectionTitle)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("settings.language.description")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer(minLength: AppSpacing.sm)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressButtonStyle())
                        .accessibilityLabel("settings.language.title")
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("settings.weather.title", systemImage: "cloud.sun.fill")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("settings.temperature.description")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            Picker("settings.temperature.title", selection: $temperatureUnit) {
                                ForEach(TemperatureUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityHint("settings.temperature.hint")
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("settings.account.title", systemImage: "person.crop.circle")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("settings.account.description")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            Button {
                                Task {
                                    await appState.logout()
                                    dismiss()
                                }
                            } label: {
                                Label("settings.sign_out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(GlassSecondaryButtonStyle(isDestructive: true))
                            .padding(.top, AppSpacing.xs)
                        }
                    }

                    #if DEBUG
                    GlassCard {
                        NavigationLink("debug.localization.title") {
                            LocalizationDebugView()
                        }
                    }
                    #endif
                }
                .frame(maxWidth: AppLayout.maxContentWidth)
                .padding(.horizontal, AppLayout.horizontalInset)
                .padding(.vertical, AppSpacing.xl)
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
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
                        Text("debug.design.card.title")
                            .font(AppTypography.cardTitle)
                        Text("debug.design.card.description")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Button("debug.design.primary_action") {}
                    .buttonStyle(GradientPrimaryButtonStyle())
                Button("debug.design.secondary_action") {}
                    .buttonStyle(GlassSecondaryButtonStyle())
                AppTextField(title: L10n.string("debug.design.field.title"), text: .constant(""), prompt: L10n.string("debug.design.field.placeholder"))
                AppEmptyState(symbol: "sparkles", title: L10n.string("debug.design.empty.title"), message: L10n.string("debug.design.empty.message"))
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
