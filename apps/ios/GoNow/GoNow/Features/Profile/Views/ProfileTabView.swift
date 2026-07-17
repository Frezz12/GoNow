import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct ProfileTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isEditing = false
    @State private var isGalleryExpanded = false
    @State private var isProfileSetupPresented = false

    var body: some View {
        NavigationStack {
            GlassScreen {
                if let user = appState.currentUser {
                    VStack(spacing: 18) {
                        if appState.shouldShowProfileSetupPrompt {
                            ProfileSetupPrompt {
                                appState.startProfileSetup()
                                isProfileSetupPresented = true
                            }
                        }

                        if appState.showsProfileCompletionIndicator {
                            if user.profileStatus == .optional {
                                ProfileCompletionNotice(
                                    status: user.profileStatus,
                                    onDismiss: { appState.dismissOptionalProfileNotice() }
                                )
                            } else {
                                ProfileCompletionNotice(status: user.profileStatus)
                            }
                        }

                        HStack(alignment: .center, spacing: 16) {
                            AvatarPicker(initials: user.initials, size: 96)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(user.displayName)
                                    .font(.title2.bold())
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(GoNowTheme.primary)
                                    Text(user.ratingText)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Рейтинг \(user.ratingText) из 5")
                                if let birthDateAndAgeText = user.birthDateAndAgeText {
                                    Label(birthDateAndAgeText, systemImage: "calendar")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 22) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Фотографии")
                                            .font(.headline)
                                        Spacer(minLength: 8)
                                        Button {
                                            withAnimation(accessibilityReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                                                isGalleryExpanded.toggle()
                                            }
                                        } label: {
                                            Label(
                                                isGalleryExpanded ? "Свернуть" : "Показать все",
                                                systemImage: isGalleryExpanded ? "chevron.up" : "chevron.right"
                                            )
                                            .labelStyle(.titleAndIcon)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(GoNowTheme.primary)
                                            .frame(minHeight: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(isGalleryExpanded ? "Свернуть фотографии" : "Показать все фотографии")
                                    }
                                    ProfilePhotoGallery(isExpanded: $isGalleryExpanded)
                                }

                                ProfileDetailsGrid(user: user)

                                if let bio = user.bio?.nonEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("О себе", systemImage: "person.text.rectangle")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(GoNowTheme.primary)
                                        Text(bio)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if let interests = user.interests, !interests.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Интересы", systemImage: "tag")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(GoNowTheme.primary)
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
            .navigationBarItems(trailing: profileSettingsMenu)
        }
        .sheet(isPresented: $isEditing) {
            if let user = appState.currentUser {
                ProfileEditorSheet(user: user)
            }
        }
        .sheet(isPresented: $isProfileSetupPresented) {
            if let user = appState.currentUser {
                ProfileSetupFlow(user: user)
            }
        }
    }

    private var profileSettingsMenu: some View {
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

private struct ProfileDetailsGrid: View {
    let user: CurrentUser

    var body: some View {
        let fields = [
            DetailField(icon: "briefcase.fill", title: "Занятие", value: user.occupation?.nonEmpty),
            DetailField(icon: "heart.text.square", title: "Семейный статус", value: user.relationshipStatus?.nonEmpty),
            DetailField(icon: "building.2.fill", title: "Город", value: user.city?.nonEmpty),
            DetailField(icon: "location.fill", title: "Место", value: user.locationLabel?.nonEmpty),
        ].filter { $0.value != nil }

        if !fields.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: field.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(GoNowTheme.primary)
                        Text(field.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.value ?? "")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
}

private struct DetailField: Identifiable {
    let icon: String
    let title: String
    let value: String?
    var id: String { title }
}

struct ProfileCompletionNotice: View {
    let status: ProfileCompletionStatus
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(status.tint)
            Text(status.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.52), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть подсказку профиля")
            }
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
