import SwiftUI

struct TasksTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ближайшие планы")
                        .font(.title2.bold())
                    TaskPreviewCard(
                        icon: "figure.walk",
                        title: "Прогулка после работы",
                        subtitle: "Сегодня · 19:00 · рядом с вами",
                        tint: GoNowTheme.primary
                    )
                    TaskPreviewCard(
                        icon: "cup.and.saucer.fill",
                        title: "Кофе и знакомство",
                        subtitle: "Завтра · 12:30 · центр города",
                        tint: .blue
                    )
                    GlassCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(GoNowTheme.accent)
                            Text("Здесь появятся ваши заявки и активности, на которые можно откликнуться.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
