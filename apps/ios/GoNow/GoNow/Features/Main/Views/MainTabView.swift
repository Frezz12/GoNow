import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCreateTaskPresented = false
    @State private var isProfileRequiredPresented = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
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

            CenterCreateTaskButton {
                if appState.currentUser?.profileStatus == .required {
                    isProfileRequiredPresented = true
                } else {
                    isCreateTaskPresented = true
                }
            }
            .padding(.bottom, 30)
        }
        .tint(GoNowTheme.primary)
        .sheet(isPresented: $isCreateTaskPresented) {
            CreateTaskSheet()
        }
        .alert("Сначала заполните профиль", isPresented: $isProfileRequiredPresented) {
            Button("Перейти в профиль") { selectedTab = 3 }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Укажите дату рождения, чтобы создавать задания и подавать заявки на активности.")
        }
    }
}

private struct CenterCreateTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let shape = Capsule()
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.18), in: Circle())
                Text("Создать")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(GoNowTheme.buttonGradient, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.84), .white.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: GoNowTheme.primary.opacity(0.32), radius: 14, y: 8)
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
