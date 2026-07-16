import SwiftUI

struct AuthenticatedHomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let user = appState.currentUser {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Добро пожаловать, \(user.displayName)").font(.title2.bold())
                                Text("GoNow скоро поможет находить активности рядом.").foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }
                        Section("Ваш аккаунт") {
                            LabeledContent("Email", value: user.email)
                            LabeledContent("Подтверждение email", value: user.emailVerified ? "Подтверждён" : "Пока не подтверждён")
                        }
                        Section("Карта GoNow") {
                            HStack(spacing: 16) {
                                MapPointMarker(size: 52)
                                    .frame(width: 56, height: 56)
                                Text("Так будет отмечаться точка активности на карте.")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        Section {
                            Button { Task { await appState.reloadUser() } } label: {
                                HStack { Text("Обновить данные"); Spacer(); if appState.isRefreshingUser { ProgressView() } }
                            }.disabled(appState.isRefreshingUser)
                            Button("Выйти", role: .destructive) { Task { await appState.logout() } }
                        }
                    }
                    .refreshable { await appState.reloadUser() }
                } else { ProgressView("Загружаем профиль") }
            }
            .navigationTitle("GoNow")
            .alert("Не удалось обновить профиль", isPresented: Binding(get: { appState.sessionError != nil }, set: { if !$0 { } })) {
                Button("Повторить") { Task { await appState.reloadUser() } }
                Button("Закрыть", role: .cancel) { }
            } message: { Text(appState.sessionError ?? "") }
        }
    }
}
