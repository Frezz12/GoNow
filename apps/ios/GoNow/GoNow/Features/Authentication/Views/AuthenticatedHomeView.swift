import SwiftUI

struct AuthenticatedHomeView: View {
    var body: some View {
        TabView {
            MapTabView()
                .tabItem { Label("Карта", systemImage: "map.fill") }
            TasksTabView()
                .tabItem { Label("Задания", systemImage: "checklist") }
            ChatTabView()
                .tabItem { Label("Чат", systemImage: "message.fill") }
            ProfileTabView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
        }
        .tint(GoNowTheme.primary)
    }
}

private struct MapTabView: View {
    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 14) {
                            MapPointMarker(size: 76)
                                .frame(width: 82, height: 82)
                            Text("Активности рядом")
                                .font(.title2.bold())
                            Text("Эта метка будет показывать место встречи. Полная карта появится на следующем этапе.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "location.circle.fill")
                                .font(.title2)
                                .foregroundStyle(GoNowTheme.primary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Геолокация")
                                    .font(.headline)
                                Text("Включите её, когда карта будет доступна, чтобы видеть встречи рядом.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Карта")
        }
    }
}

private struct TasksTabView: View {
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
            .navigationTitle("Задания")
        }
    }
}

private struct ChatTabView: View {
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
            .navigationTitle("Чат")
        }
    }
}

private struct ProfileTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            GlassScreen {
                if let user = appState.currentUser {
                    VStack(spacing: 16) {
                        GlassCard {
                            HStack(spacing: 16) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(GoNowTheme.primary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(user.displayName)
                                        .font(.title3.bold())
                                    Text(user.email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Label(
                                        user.emailVerified ? "Email подтверждён" : "Email пока не подтверждён",
                                        systemImage: user.emailVerified ? "checkmark.seal.fill" : "exclamationmark.circle.fill"
                                    )
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(user.emailVerified ? .green : .orange)
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        Button {
                            Task { await appState.reloadUser() }
                        } label: {
                            HStack(spacing: 8) {
                                if appState.isRefreshingUser { ProgressView().tint(.white) }
                                Text(appState.isRefreshingUser ? "Обновляем…" : "Обновить профиль")
                            }
                        }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(appState.isRefreshingUser)
                        .accessibilityHint("Загрузить актуальные данные профиля")

                        Button("Выйти из аккаунта", role: .destructive) {
                            Task { await appState.logout() }
                        }
                        .buttonStyle(GlassSecondaryButtonStyle(isDestructive: true))
                        .accessibilityHint("Завершить сеанс на этом устройстве")
                    }
                } else {
                    ProgressView("Загружаем профиль")
                }
            }
            .navigationTitle("Профиль")
            .alert(
                "Не удалось обновить профиль",
                isPresented: Binding(
                    get: { appState.sessionError != nil },
                    set: { if !$0 { appState.dismissSessionError() } }
                )
            ) {
                Button("Повторить") { Task { await appState.reloadUser() } }
                Button("Закрыть", role: .cancel) { appState.dismissSessionError() }
            } message: {
                Text(appState.sessionError ?? "")
            }
        }
    }
}

private struct GlassScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, 32)
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
