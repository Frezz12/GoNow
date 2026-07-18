import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCreateTaskPresented = false
    @State private var isProfileRequiredPresented = false
    @State private var isProfileSetupPresented = false
    @State private var selectedTab: AppTab = .map
    @State private var isMapSearchActive = false

    var body: some View {
        ZStack {
            // The native tab bar renders with the system Liquid Glass treatment on iOS 26.
            // It is more legible and responsive than a custom material imitation.
            TabView(selection: $selectedTab) {
                MapTabView(isSearchActive: $isMapSearchActive) { selectedTab = .profile }
                    .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.symbol) }
                    .tag(AppTab.map)
                TasksTabView()
                    .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.symbol) }
                    .tag(AppTab.tasks)
                ChatTabView()
                    .tabItem { Label(AppTab.chat.title, systemImage: AppTab.chat.symbol) }
                    .tag(AppTab.chat)
                ProfileTabView()
                    .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.symbol) }
                    .tag(AppTab.profile)
            }

            if selectedTab == .map && appState.shouldShowProfileSetupPrompt {
                ProfileSetupPrompt {
                    appState.startProfileSetup()
                    isProfileSetupPresented = true
                }
                .padding(.horizontal, AppLayout.horizontalInset)
                .padding(.bottom, 164)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if selectedTab == .map {
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

                MapSearchButton {
                    withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                        isMapSearchActive = true
                    }
                }
                .padding(.trailing, AppLayout.horizontalInset)
                .padding(.bottom, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .tint(AppColors.accentPrimary)
        .onChange(of: selectedTab) { _, tab in
            if tab != .map {
                isMapSearchActive = false
            }
        }
        .sheet(isPresented: $isCreateTaskPresented) {
            CreateTaskSheet()
        }
        .sheet(isPresented: $isProfileSetupPresented) {
            if let user = appState.currentUser {
                ProfileSetupFlow(user: user)
            }
        }
        .alert("Сначала заполните профиль", isPresented: $isProfileRequiredPresented) {
            Button("Перейти в профиль") { selectedTab = .profile }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Укажите дату рождения, чтобы создавать задания и подавать заявки на активности.")
        }
    }
}

private struct MapSearchButton: View {
    let action: () -> Void

    var body: some View {
        let shape = Circle()

        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.headline.weight(.semibold))
                .frame(width: 54, height: 54)
        }
        .foregroundStyle(AppColors.textPrimary)
        .background(.regularMaterial, in: shape)
        .glassEffect(.regular, in: shape)
        .overlay { shape.strokeBorder(AppColors.glassBorder.opacity(0.72), lineWidth: 1) }
        .appShadow(.floating)
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel("Поиск задач")
        .accessibilityHint("Открыть поиск задач и активностей")
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
            .foregroundStyle(AppColors.textOnAccent)
            .padding(.horizontal, AppSpacing.xl)
            .frame(minWidth: 168, minHeight: 54)
            .background(AppGradients.brand, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [AppColors.glassHighlight.opacity(0.36), AppColors.glassHighlight.opacity(0.08), .clear],
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
                            colors: [AppColors.glassHighlight.opacity(0.86), AppColors.glassHighlight.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .appShadow(.floating)
        }
        .buttonStyle(AppPressButtonStyle())
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
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Новая задача")
                        .font(.title.bold())
                    Text("Начните с названия. Настройки времени, места и участников появятся следующим шагом.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Название")
                            .font(.subheadline.weight(.medium))
                        TextField("Например, прогулка в парке", text: $title)
                            .focused($isTitleFocused)
                            .padding(.horizontal, AppSpacing.md)
                            .frame(minHeight: 54)
                            .liquidGlassField(isInvalid: false, isFocused: isTitleFocused)
                    }

                    Button("Продолжить") { dismiss() }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(AppSpacing.xl)
            }
            .navigationTitle("Создать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(AppColors.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
