import SwiftUI

struct TasksTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Ближайшие планы")
                        .font(AppTypography.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    TaskPreviewCard(
                        icon: "figure.walk",
                        title: "Прогулка после работы",
                        subtitle: "Сегодня · 19:00 · рядом с вами",
                        tint: AppColors.accentPrimary
                    )
                    TaskPreviewCard(
                        icon: "cup.and.saucer.fill",
                        title: "Кофе и знакомство",
                        subtitle: "Завтра · 12:30 · центр города",
                        tint: AppColors.locationAccent
                    )
                    GlassCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                            .foregroundStyle(AppColors.accentSecondary)
                            Text("Здесь появятся ваши заявки и активности, на которые можно откликнуться.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

private struct TaskPreviewCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        GlassCard {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                    .font(AppTypography.cardTitle)
                    Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
    }
}
