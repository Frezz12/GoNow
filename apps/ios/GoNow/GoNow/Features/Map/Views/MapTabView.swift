import SwiftUI
import Foundation

struct MapTabView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isSearchActive: Bool
    @State private var isNotificationsPresented = false
    private let notificationCount = 0
    let onProfileTap: () -> Void

    var body: some View {
        ZStack {
            MapPreviewSurface()
                .ignoresSafeArea()

            Group {
                if isSearchActive {
                    MapTaskSearchBar(isSearchActive: $isSearchActive)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(alignment: .top) {
                        MapWeatherWidget(
                            profileLatitude: appState.currentUser?.latitude,
                            profileLongitude: appState.currentUser?.longitude,
                            profileLocationLabel: appState.currentUser?.locationLabel
                        )
                        Spacer(minLength: AppSpacing.md)

                        Menu {
                            Button {
                                onProfileTap()
                            } label: {
                                Label("Профиль", systemImage: "person.crop.circle")
                            }

                            Button {
                                isNotificationsPresented = true
                            } label: {
                                Label(
                                    notificationCount > 0 ? "Уведомления (\(notificationCount))" : "Уведомления",
                                    systemImage: notificationCount > 0 ? "bell.badge.fill" : "bell"
                                )
                            }
                        } label: {
                            profileAvatar
                        }
                        .accessibilityLabel(profileMenuAccessibilityLabel)
                        .accessibilityHint("Открыть профиль или уведомления")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.top, AppSpacing.sm)
            .padding(.horizontal, AppLayout.horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(AppAnimation.standard, value: isSearchActive)
        }
        .alert("Уведомления", isPresented: $isNotificationsPresented) {
            Button("Готово", role: .cancel) {}
        } message: {
            Text("Новых уведомлений пока нет.")
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
            return "Меню профиля"
        }
        return "Меню профиля. \(status.accessibilityDescription)"
    }
}

private struct MapTaskSearchBar: View {
    @Binding var isSearchActive: Bool
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()

        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.accentPrimary)

            TextField("Поиск задач и активностей", text: $query)
                .font(AppTypography.body)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Поиск задач и активностей")

            Button {
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
            .accessibilityLabel("Закрыть поиск")
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

private struct MapPreviewSurface: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [AppColors.backgroundSecondary, AppColors.surfaceSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Canvas { context, size in
                    var river = Path()
                    river.move(to: CGPoint(x: -20, y: size.height * 0.72))
                    river.addCurve(
                        to: CGPoint(x: size.width + 30, y: size.height * 0.30),
                        control1: CGPoint(x: size.width * 0.28, y: size.height * 0.94),
                        control2: CGPoint(x: size.width * 0.68, y: size.height * 0.12)
                    )
                    context.stroke(river, with: .color(AppColors.surfacePrimary.opacity(0.62)), lineWidth: 22)
                    for (index, ratio) in [0.16, 0.34, 0.56, 0.78].enumerated() {
                        var street = Path()
                        street.move(to: CGPoint(x: -20, y: size.height * ratio))
                        street.addCurve(
                            to: CGPoint(x: size.width + 20, y: size.height * (ratio + (index.isMultiple(of: 2) ? 0.13 : -0.11))),
                            control1: CGPoint(x: size.width * 0.30, y: size.height * (ratio - 0.08)),
                            control2: CGPoint(x: size.width * 0.72, y: size.height * (ratio + 0.08))
                        )
                        context.stroke(street, with: .color(AppColors.surfacePrimary.opacity(0.82)), lineWidth: index == 1 ? 11 : 7)
                    }
                    for ratio in [0.19, 0.47, 0.73, 0.91] {
                        var street = Path()
                        street.move(to: CGPoint(x: size.width * ratio, y: -20))
                        street.addLine(to: CGPoint(x: size.width * (ratio - 0.18), y: size.height + 20))
                        context.stroke(street, with: .color(AppColors.surfacePrimary.opacity(0.74)), lineWidth: 6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(AppColors.success.opacity(0.22))
                        .frame(width: proxy.size.width * 0.38, height: proxy.size.height * 0.24)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -22, y: 126)
                }
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(AppColors.success.opacity(0.16))
                        .frame(width: proxy.size.width * 0.44, height: proxy.size.height * 0.20)
                        .rotationEffect(.degrees(18))
                        .offset(x: 30, y: -120)
                }
                MapPointMarker(size: 44)
                    .position(x: proxy.size.width * 0.42, y: proxy.size.height * 0.42)
                MapPointMarker(size: 34)
                    .opacity(0.88)
                    .position(x: proxy.size.width * 0.70, y: proxy.size.height * 0.62)
            }
        }
        .accessibilityLabel("Карта активностей")
    }
}
