import SwiftUI
import Foundation

struct MapTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isSearchActive: Bool
    @ObservedObject var model: ActivityMapViewModel
    @ObservedObject var location: DeviceLocationProvider
    @State private var isNotificationsPresented = false
    private let notificationCount = 0
    let onProfileTap: () -> Void

    var body: some View {
        ZStack {
            ActivityMapView(model: model, location: location)

            Group {
                if isSearchActive {
                    MapTaskSearchBar(query: $model.searchQuery, isSearchActive: $isSearchActive)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(alignment: .top) {
                        MapWeatherWidget(
                            profileLatitude: appState.currentUser?.latitude,
                            profileLongitude: appState.currentUser?.longitude,
                            deviceLocation: location
                        )
                        Spacer(minLength: AppSpacing.md)

                        Menu {
                            Button {
                                onProfileTap()
                            } label: {
                                Label("tab.profile", systemImage: "person.crop.circle")
                            }

                            Button {
                                isNotificationsPresented = true
                            } label: {
                                Label(
                                    notificationCount > 0 ? L10n.string("map.notifications.count \(notificationCount)") : L10n.string("map.notifications.title"),
                                    systemImage: notificationCount > 0 ? "bell.badge.fill" : "bell"
                                )
                            }
                        } label: {
                            profileAvatar
                        }
                        .accessibilityLabel(profileMenuAccessibilityLabel)
                        .accessibilityHint("map.profile_menu.hint")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.top, AppSpacing.sm)
            .padding(.horizontal, AppLayout.horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : AppAnimation.standard, value: isSearchActive)
        }
        .alert("map.notifications.title", isPresented: $isNotificationsPresented) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("map.notifications.empty")
        }
    }

    private var profileAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            ProfileAvatar(initials: appState.currentUser?.initials ?? "G", size: 48, imageData: appState.avatarImageData)
                .padding(AppSpacing.xxs)
                .background(.regularMaterial, in: Circle())
                .glassEffect(.regular, in: Circle())
                .overlay { Circle().strokeBorder(AppColors.glassBorder.opacity(0.72), lineWidth: 1) }
                .appShadow(.floating)
            if appState.showsProfileCompletionIndicator, let status = appState.currentUser?.profileStatus {
                Image(systemName: "exclamationmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 20, height: 20)
                    .background(status.tint, in: Circle())
                    .overlay { Circle().strokeBorder(AppColors.glassBorder, lineWidth: 2) }
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var profileMenuAccessibilityLabel: String {
        guard appState.showsProfileCompletionIndicator,
              let status = appState.currentUser?.profileStatus else {
            return L10n.string("profile.menu")
        }
        return "\(L10n.string("profile.menu")). \(status.accessibilityDescription)"
    }
}

private struct MapTaskSearchBar: View {
    @Binding var query: String
    @Binding var isSearchActive: Bool
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()

        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.accentPrimary)

            TextField("map.search.placeholder", text: $query)
                .font(AppTypography.body)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .accessibilityLabel("map.search.placeholder")

            Button {
                query = ""
                withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                    isSearchActive = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: AppLayout.minimumTouchTarget, height: AppLayout.minimumTouchTarget)
                    .background(AppColors.surfaceElevated.opacity(0.55), in: Circle())
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel("map.search.close")
        }
        .padding(.leading, AppSpacing.md)
        .padding(.trailing, AppSpacing.xxs)
        .frame(minHeight: 56)
        .background(.regularMaterial, in: shape)
        .glassEffect(.regular, in: shape)
        .overlay { shape.strokeBorder(AppColors.glassBorder.opacity(0.76), lineWidth: 1) }
        .appShadow(.floating)
        .task { isSearchFocused = true }
    }
}
