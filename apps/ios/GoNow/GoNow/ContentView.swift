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
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle.fill").font(.system(size: 56)).foregroundStyle(GoNowTheme.primary)
            Text("GoNow").font(.largeTitle.bold())
            ProgressView("Восстанавливаем сессию")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoNowTheme.background)
    }
}
