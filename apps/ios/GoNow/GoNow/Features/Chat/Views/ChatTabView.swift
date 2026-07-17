import SwiftUI

struct ChatTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Чаты")
                        .font(AppTypography.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    AppEmptyState(
                        symbol: "bubble.left.and.bubble.right",
                        title: "Пока здесь тихо",
                        message: "Когда вы присоединитесь к активности, все сообщения будут собраны в этом месте."
                    )
                }
            }
        }
    }
}
