import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        GlassScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    GlassCard(style: .prominent) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("settings.language.title")
                                .font(AppTypography.sectionTitle)
                            Text("settings.language.description")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                                languageRow(language)
                                if index < AppLanguage.allCases.count - 1 {
                                    Divider().overlay(AppColors.divider)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: AppLayout.maxContentWidth)
                .padding(.horizontal, AppLayout.horizontalInset)
                .padding(.vertical, AppSpacing.xl)
            }
        }
        .navigationTitle("settings.language.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        Button {
            localizationManager.select(language)
        } label: {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(language.nativeDisplayName)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    if language == .system {
                        Text("settings.language.system.description")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: AppSpacing.md)
                if localizationManager.selectedLanguage == language {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(AppColors.accentPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: AppLayout.minimumTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(language.nativeDisplayName)
        .accessibilityAddTraits(localizationManager.selectedLanguage == language ? .isSelected : [])
    }
}
