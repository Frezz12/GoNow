import SwiftUI

struct ChatTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Чаты")
                        .font(.title2.bold())
                    GlassCard {
                        HStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(GoNowTheme.primary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Общение по активности")
                                    .font(.headline)
                                Text("Чат откроется, когда участники подтвердят встречу.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Пока здесь тихо")
                        .font(.headline)
                    Text("Когда вы присоединитесь к активности, все сообщения будут собраны в этом месте.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
