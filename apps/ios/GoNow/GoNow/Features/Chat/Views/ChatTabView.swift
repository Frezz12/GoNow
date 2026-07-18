import SwiftUI

struct ChatTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("chat.title")
                        .font(AppTypography.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    AppEmptyState(
                        symbol: "bubble.left.and.bubble.right",
                        title: "chat.empty.title",
                        message: "chat.empty.message"
                    )
                }
            }
        }
    }
}
