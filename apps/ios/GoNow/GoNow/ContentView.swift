import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                LaunchView(errorMessage: appState.sessionError) {
                    Task { await appState.restoreSession() }
                }
            case .unauthenticated: AuthenticationFlowView()
            case .authenticated: MainTabView(activityRepository: appState.activityMapRepository)
            }
        }
        .task { await appState.restoreSession() }
        .background(AppColors.backgroundPrimary)
    }
}

private struct LaunchView: View {
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accentPrimary)
            Text(verbatim: "GoNow")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            if let errorMessage {
                ErrorMessage(text: errorMessage)
                    .multilineTextAlignment(.center)
                Button("common.retry", action: retry)
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .frame(maxWidth: AppLayout.maxContentWidth)
            } else {
                ProgressView("launch.restoring_session")
                    .tint(AppColors.accentPrimary)
            }
        }
        .padding(AppLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}
