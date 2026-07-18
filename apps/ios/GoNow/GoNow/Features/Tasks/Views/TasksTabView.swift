import SwiftUI

struct TasksTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("tasks.title")
                        .font(AppTypography.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    TaskPreviewCard(
                        icon: "figure.walk",
                        title: L10n.string("tasks.preview.walk.title"),
                        subtitle: L10n.string("tasks.preview.walk.subtitle"),
                        tint: AppColors.accentPrimary
                    )
                    TaskPreviewCard(
                        icon: "cup.and.saucer.fill",
                        title: L10n.string("tasks.preview.coffee.title"),
                        subtitle: L10n.string("tasks.preview.coffee.subtitle"),
                        tint: AppColors.locationAccent
                    )
                    GlassCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                            .foregroundStyle(AppColors.accentSecondary)
                            Text("tasks.empty.message")
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
