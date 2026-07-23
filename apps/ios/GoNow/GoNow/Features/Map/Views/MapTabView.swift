import SwiftUI
import Foundation

struct MapTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isSearchActive: Bool
    @ObservedObject var model: ActivityMapViewModel
    @ObservedObject var location: DeviceLocationProvider
    let activityRepository: any ActivityRepository
    let onProfileTap: () -> Void
    let onNotificationsTap: () -> Void

    var body: some View {
        ZStack {
            ActivityMapView(model: model, location: location, activityRepository: activityRepository)

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
                            Button(action: onProfileTap) {
                                Label("tab.profile", systemImage: "person.crop.circle")
                            }

                            Button(action: onNotificationsTap) {
                                Label(
                                    appState.unreadNotificationCount > 0
                                        ? L10n.format("map.notifications.count %lld", appState.unreadNotificationCount)
                                        : L10n.string("map.notifications.title"),
                                    systemImage: appState.unreadNotificationCount > 0 ? "bell.badge.fill" : "bell"
                                )
                            }
                        } label: {
                            profileAvatar
                        }
                        .buttonStyle(AppPressButtonStyle())
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
            if appState.unreadNotificationCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(appState.unreadNotificationCount > 99 ? "99+" : "\(appState.unreadNotificationCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(AppColors.textOnAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 18)
                .background(AppColors.error, in: Capsule())
                .overlay { Capsule().strokeBorder(AppColors.glassHighlight, lineWidth: 1) }
                .offset(x: 4, y: -4)
                .accessibilityHidden(true)
            }
        }
    }

    private var profileMenuAccessibilityLabel: String {
        var details: [String] = [L10n.string("profile.menu")]
        if appState.unreadNotificationCount > 0 {
            details.append(L10n.format("map.notifications.count %lld", appState.unreadNotificationCount))
        }
        if appState.showsProfileCompletionIndicator,
           let status = appState.currentUser?.profileStatus {
            details.append(status.accessibilityDescription)
        }
        return details.joined(separator: ". ")
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
