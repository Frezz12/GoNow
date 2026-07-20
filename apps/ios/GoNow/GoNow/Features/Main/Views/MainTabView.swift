import CoreLocation
import Combine
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var activityMapModel: ActivityMapViewModel
    @StateObject private var location = DeviceLocationProvider()
    private let mapActivityRepository: any MapActivityRepository
    @State private var isCreateTaskPresented = false
    @State private var isNotificationsPresented = false
    @State private var isProfileRequiredPresented = false
    @State private var isProfileSetupPresented = false
    @State private var selectedTab: AppTab = .map
    @State private var isMapSearchActive = false

    init(activityRepository: any MapActivityRepository) {
        mapActivityRepository = activityRepository
        _activityMapModel = StateObject(wrappedValue: ActivityMapViewModel(repository: activityRepository))
    }

    var body: some View {
        ZStack {
            // The native tab bar renders with the system Liquid Glass treatment on iOS 26.
            // It is more legible and responsive than a custom material imitation.
            TabView(selection: $selectedTab) {
                MapTabView(
                    isSearchActive: $isMapSearchActive,
                    model: activityMapModel,
                    location: location,
                    activityRepository: appState.activityRepository,
                    onProfileTap: { selectedTab = .profile },
                    onNotificationsTap: { isNotificationsPresented = true }
                )
                    .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.symbol) }
                    .tag(AppTab.map)
                ActivitiesTabView(
                    mapRepository: mapActivityRepository,
                    detailRepository: appState.activityRepository,
                    location: location
                )
                    .tabItem { Label(AppTab.activities.title, systemImage: AppTab.activities.symbol) }
                    .tag(AppTab.activities)
                ChatTabView()
                    .tabItem { Label(AppTab.chat.title, systemImage: AppTab.chat.symbol) }
                    .badge(appState.unreadChatCount)
                    .tag(AppTab.chat)
                ProfileTabView(onNotificationsTap: { isNotificationsPresented = true })
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
        .task {
            appState.startNotificationUpdates()
            await appState.reloadNotificationCount()
            await appState.reloadChatUnreadCount()
            await pushNotifications.requestAuthorizationIfNeeded()
            if let token = pushNotifications.deviceToken {
                await appState.registerPushToken(token)
            }
            if pushNotifications.pendingDestination != nil {
                isNotificationsPresented = true
            }
            if let action = pushNotifications.pendingAction {
                pushNotifications.consumePendingAction()
                await appState.performPushAction(action)
            }
        }
        .onReceive(pushNotifications.$deviceToken.compactMap { $0 }) { token in
            Task { await appState.registerPushToken(token) }
        }
        .onChange(of: pushNotifications.pendingDestination) { _, destination in
            if destination != nil { isNotificationsPresented = true }
        }
        .onChange(of: pushNotifications.pendingAction) { _, action in
            guard let action else { return }
            pushNotifications.consumePendingAction()
            Task {
                await appState.performPushAction(action)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .map {
                isMapSearchActive = false
                activityMapModel.searchQuery = ""
            }
            if tab == .chat {
                Task { await appState.reloadChatUnreadCount() }
            }
        }
        .sheet(isPresented: $isCreateTaskPresented) {
            ActivityCreationFlow(repository: appState.activityRepository, location: location) { _ in
                activityMapModel.reload()
            }
        }
        .sheet(isPresented: $isNotificationsPresented) {
            NotificationsView()
        }
        .sheet(isPresented: $isProfileSetupPresented) {
            if let user = appState.currentUser {
                ProfileSetupFlow(user: user)
            }
        }
        .alert("profile.required.title", isPresented: $isProfileRequiredPresented) {
            Button("profile.required.open") { selectedTab = .profile }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.required.message")
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
        .accessibilityLabel("map.search.accessibility")
        .accessibilityHint("map.search.hint")
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
                Text("task.create.action")
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
        .accessibilityLabel("task.create.accessibility")
        .accessibilityHint("task.create.hint")
    }
}
