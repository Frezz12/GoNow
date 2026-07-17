import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .launching: LaunchView()
            case .unauthenticated: AuthenticationFlowView()
            case .authenticated: MainTabView()
            }
        }
        .task { await appState.restoreSession() }
        .background(AppColors.backgroundPrimary)
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accentPrimary)
            Text("GoNow")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            ProgressView("Восстанавливаем сессию")
                .tint(AppColors.accentPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}
