import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct ProfileTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            GlassScreen {
                if let user = appState.currentUser {
                    VStack(spacing: 18) {
                        VStack(spacing: 8) {
                            AvatarPicker(initials: user.initials, size: 104)
                            Text(user.displayName)
                                .font(.title2.bold())
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(GoNowTheme.primary)
                                Text(user.ratingText)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Рейтинг \(user.ratingText) из 5")
                        }
                        .frame(maxWidth: .infinity)

                        ProfilePhotoGallery()

                        if user.profileStatus != .complete {
                            ProfileCompletionNotice(status: user.profileStatus)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(GoNowTheme.primary)
                                        .frame(width: 22)
                                    Text(user.age.map { "\($0) лет" } ?? "Возраст не указан")
                                        .font(.subheadline.weight(.medium))
                                    Spacer(minLength: 0)
                                }

                                Divider()

                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "person.text.rectangle")
                                        .foregroundStyle(GoNowTheme.primary)
                                        .frame(width: 22)
                                    if let bio = user.bio?.nonEmpty {
                                        Text(bio)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Добавьте пару строк о себе — так легче найти людей для похожих активностей.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "tag")
                                        .foregroundStyle(GoNowTheme.primary)
                                        .frame(width: 22)
                                    if let interests = user.interests, !interests.isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                                        ForEach(interests, id: \.self) { interest in
                                            Text(interest)
                                                .font(.footnote.weight(.medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(GoNowTheme.primary.opacity(0.12), in: Capsule())
                                                .foregroundStyle(GoNowTheme.primary)
                                        }
                                    }
                                    } else {
                                        Text("Добавьте интересы: прогулки, спорт, настольные игры — что вам ближе.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Загружаем профиль")
                }
            }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { isEditing = true } label: {
                            Label("Редактировать профиль", systemImage: "square.and.pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await appState.logout() }
                        } label: {
                            Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Настройки профиля")
                    .accessibilityHint("Открыть меню, включая выход из аккаунта")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let user = appState.currentUser {
                ProfileEditorSheet(user: user)
            }
        }
    }
}

struct ProfileCompletionNotice: View {
    let status: ProfileCompletionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(status.tint)
            Text(status.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(status.tint.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
