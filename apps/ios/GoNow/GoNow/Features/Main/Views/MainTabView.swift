import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCreateTaskPresented = false
    @State private var isProfileRequiredPresented = false
    @State private var isProfileSetupPresented = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                MapTabView { selectedTab = 3 }
                    .tabItem { Label("Карта", systemImage: "map.fill") }
                    .tag(0)
                TasksTabView()
                    .tabItem { Label("Задания", systemImage: "checklist") }
                    .tag(1)
                ChatTabView()
                    .tabItem { Label("Чат", systemImage: "message.fill") }
                    .tag(2)
                ProfileTabView()
                    .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
                    .tag(3)
            }

            if selectedTab == 0 && appState.shouldShowProfileSetupPrompt {
                ProfileSetupPrompt {
                    appState.startProfileSetup()
                    isProfileSetupPresented = true
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 164)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if selectedTab == 0 {
                MapCreateTaskButton {
                    if appState.currentUser?.profileStatus == .required {
                        isProfileRequiredPresented = true
                    } else {
                        isCreateTaskPresented = true
                    }
                }
                .padding(.bottom, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .tint(GoNowTheme.primary)
        .sheet(isPresented: $isCreateTaskPresented) {
            CreateTaskSheet()
        }
        .sheet(isPresented: $isProfileSetupPresented) {
            if let user = appState.currentUser {
                ProfileSetupFlow(user: user)
            }
        }
        .alert("Сначала заполните профиль", isPresented: $isProfileRequiredPresented) {
            Button("Перейти в профиль") { selectedTab = 3 }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Укажите дату рождения, чтобы создавать задания и подавать заявки на активности.")
        }
    }
}

private struct MapCreateTaskButton: View {
    let createAction: () -> Void

    var body: some View {
        let shape = Capsule()

        Button(action: createAction) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                Text("Создать")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(minWidth: 166, minHeight: 56)
            .background(.ultraThinMaterial, in: shape)
            .background(GoNowTheme.buttonGradient.opacity(0.76), in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.36), .white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.86), .white.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: GoNowTheme.accent.opacity(0.36), radius: 16, y: 7)
            .shadow(color: GoNowTheme.primary.opacity(0.24), radius: 26, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Создать задачу")
        .accessibilityHint("Открыть форму создания новой задачи")
    }
}

private struct CreateTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Новая задача")
                        .font(.title.bold())
                    Text("Начните с названия. Настройки времени, места и участников появятся следующим шагом.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Название")
                            .font(.subheadline.weight(.medium))
                        TextField("Например, прогулка в парке", text: $title)
                            .focused($isTitleFocused)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .liquidGlassField(isInvalid: false, isFocused: isTitleFocused)
                    }

                    Button("Продолжить") { dismiss() }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Создать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(GoNowTheme.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
