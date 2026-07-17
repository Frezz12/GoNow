import SwiftUI
import Foundation

struct MapTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isNotificationsPresented = false
    private let notificationCount = 0
    let onProfileTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapPreviewSurface()
                .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 8) {
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
            .padding(.top, 12)
            .padding(.trailing, 20)
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
                .padding(3)
                .background(.thinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.82), lineWidth: 1) }
            if appState.showsProfileCompletionIndicator, let status = appState.currentUser?.profileStatus {
                Image(systemName: "exclamationmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(status.tint, in: Circle())
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
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

private struct MapPreviewSurface: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.82, green: 0.92, blue: 0.88), Color(red: 0.89, green: 0.93, blue: 0.96)],
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
                    context.stroke(river, with: .color(Color.white.opacity(0.62)), lineWidth: 22)
                    for (index, ratio) in [0.16, 0.34, 0.56, 0.78].enumerated() {
                        var street = Path()
                        street.move(to: CGPoint(x: -20, y: size.height * ratio))
                        street.addCurve(
                            to: CGPoint(x: size.width + 20, y: size.height * (ratio + (index.isMultiple(of: 2) ? 0.13 : -0.11))),
                            control1: CGPoint(x: size.width * 0.30, y: size.height * (ratio - 0.08)),
                            control2: CGPoint(x: size.width * 0.72, y: size.height * (ratio + 0.08))
                        )
                        context.stroke(street, with: .color(Color.white.opacity(0.82)), lineWidth: index == 1 ? 11 : 7)
                    }
                    for ratio in [0.19, 0.47, 0.73, 0.91] {
                        var street = Path()
                        street.move(to: CGPoint(x: size.width * ratio, y: -20))
                        street.addLine(to: CGPoint(x: size.width * (ratio - 0.18), y: size.height + 20))
                        context.stroke(street, with: .color(Color.white.opacity(0.74)), lineWidth: 6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.green.opacity(0.22))
                        .frame(width: proxy.size.width * 0.38, height: proxy.size.height * 0.24)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -22, y: 126)
                }
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.green.opacity(0.16))
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
