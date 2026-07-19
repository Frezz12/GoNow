import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct ProfileTabView: View {
    @EnvironmentObject private var appState: AppState
    let onNotificationsTap: () -> Void
    @State private var isEditing = false
    @State private var isSettingsPresented = false
    @State private var isGalleryExpanded = false
    @State private var isProfileSetupPresented = false
    @State private var isSocialHubPresented = false
    @State private var isAboutExpanded = false

    var body: some View {
        NavigationStack {
            GlassScreen {
                if let user = appState.currentUser {
                    VStack(spacing: AppSpacing.lg) {
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

                        HStack(alignment: .center, spacing: AppSpacing.md) {
                            AvatarPicker(initials: user.initials, size: 96)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(user.displayName)
                                    .font(AppTypography.screenTitle)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("@\(user.username)")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundStyle(AppColors.accentPrimary)
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Username: \(user.username)")
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)

                        ProfileAboutDisclosure(user: user, isExpanded: $isAboutExpanded)

                        Button { isSocialHubPresented = true } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "person.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppColors.accentPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(AppColors.accentPrimary.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Друзья и приглашения")
                                        .font(AppTypography.bodyMedium)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("Найдите людей, ответьте на заявки или позовите встретиться")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.textMuted)
                            }
                            .padding(AppSpacing.md)
                            .glassSurface(.regular, cornerRadius: AppRadius.card)
                        }
                        .buttonStyle(AppPressButtonStyle())

                        Label("Посты", systemImage: "square.grid.2x2.fill")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProfilePostsView(isGalleryExpanded: $isGalleryExpanded)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView("profile.loading")
                }
            }
            .alert(
                "profile.reload.error.title",
                isPresented: Binding(
                    get: { appState.sessionError != nil },
                    set: { if !$0 { appState.dismissSessionError() } }
                )
            ) {
                Button("common.retry") { Task { await appState.reloadUser() } }
                Button("common.close", role: .cancel) { appState.dismissSessionError() }
            } message: {
                Text(appState.sessionError ?? "")
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    profileNotificationsButton
                    profileSettingsButton
                }
            }
            .navigationDestination(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .navigationDestination(isPresented: $isSocialHubPresented) {
                SocialHubView()
            }
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

    private var profileNotificationsButton: some View {
        Button(action: onNotificationsTap) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: appState.unreadNotificationCount > 0 ? "bell.fill" : "bell")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)

                if appState.unreadNotificationCount > 0 {
                    Text(appState.unreadNotificationCount > 99 ? "99+" : "\(appState.unreadNotificationCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(AppColors.error, in: Capsule())
                        .overlay { Capsule().strokeBorder(AppColors.glassHighlight, lineWidth: 1) }
                        .offset(x: 3, y: 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(
            appState.unreadNotificationCount > 0
                ? "Уведомления, непрочитанных: \(appState.unreadNotificationCount)"
                : "Уведомления"
        )
        .accessibilityHint("Открывает список уведомлений")
    }

    private var profileSettingsButton: some View {
        Menu {
            Button { isEditing = true } label: {
                Label("profile.edit", systemImage: "square.and.pencil")
            }
            Button { isSettingsPresented = true } label: {
                Label("settings.title", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("profile.menu")
        .accessibilityHint("profile.menu.hint")
    }
}

private struct ProfileAboutDisclosure: View {
    let user: CurrentUser
    @Binding var isExpanded: Bool

    var body: some View {
        GlassCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    Divider().overlay(AppColors.divider)
                    if !hasProfileInformation {
                        Label("Информация пока не заполнена", systemImage: "info.circle")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    profileFacts
                    ProfileDetailsGrid(user: user)
                    if let bio = user.bio?.nonEmpty {
                        profileTextSection(
                            title: L10n.string("profile.bio.title"),
                            symbol: "person.text.rectangle",
                            text: bio
                        )
                    }
                    if let interests = user.interests, !interests.isEmpty {
                        tagSection(
                            title: L10n.string("profile.interests.title"),
                            symbol: "tag",
                            values: interests,
                            tint: AppColors.accentPrimary
                        )
                    }
                    if let languages = user.languages, !languages.isEmpty {
                        tagSection(
                            title: L10n.string("profile.languages.title"),
                            symbol: "globe",
                            values: languages,
                            tint: AppColors.accentSecondary
                        )
                    }
                }
                .padding(.top, AppSpacing.sm)
            } label: {
                Label(isExpanded ? "Скрыть информацию" : "Информация о себе", systemImage: "person.text.rectangle")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget, alignment: .leading)
            }
            .tint(AppColors.accentPrimary)
            .accessibilityHint(isExpanded ? "Сворачивает данные профиля" : "Показывает данные профиля")
        }
    }

    private var hasProfileInformation: Bool {
        user.birthDateAndAgeText != nil
            || user.profileLocationText != nil
            || user.occupation?.nonEmpty != nil
            || user.relationshipStatus?.nonEmpty != nil
            || user.availability?.nonEmpty != nil
            || user.preferredGroupSizeText != nil
            || user.bio?.nonEmpty != nil
            || user.interests?.isEmpty == false
            || user.languages?.isEmpty == false
    }

    @ViewBuilder
    private var profileFacts: some View {
        if user.birthDateAndAgeText != nil || user.profileLocationText != nil {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let birthDateAndAgeText = user.birthDateAndAgeText {
                    Label(birthDateAndAgeText, systemImage: "calendar")
                }
                if let locationText = user.profileLocationText {
                    Label(locationText, systemImage: "mappin.and.ellipse")
                        .accessibilityLabel(L10n.format("profile.location.accessibility %@", locationText))
                }
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func profileTextSection(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label(title, systemImage: symbol)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.accentPrimary)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tagSection(title: String, symbol: String, values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label(title, systemImage: symbol)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.accentPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(AppTypography.badge)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(tint.opacity(0.13), in: Capsule())
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

private struct ProfileDetailsGrid: View {
    let user: CurrentUser

    var body: some View {
        let fields = [
            DetailField(icon: "briefcase.fill", title: L10n.string("profile.occupation.title"), value: user.occupation?.nonEmpty),
            DetailField(icon: "heart.text.square", title: L10n.string("profile.relationship.title"), value: user.relationshipStatus?.nonEmpty),
            DetailField(icon: "clock.fill", title: L10n.string("profile.availability.title"), value: user.availability?.nonEmpty),
            DetailField(icon: "person.3.fill", title: L10n.string("profile.group.title"), value: user.preferredGroupSizeText),
        ].filter { $0.value != nil }

        if !fields.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Image(systemName: field.icon)
                            .font(AppTypography.captionStrong)
                            .foregroundStyle(AppColors.accentPrimary)
                        Text(field.title)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(field.value ?? "")
                            .font(AppTypography.bodyMedium)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .padding(AppSpacing.sm)
                    .glassSurface(.subtle, cornerRadius: AppRadius.control)
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
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(status.tint)
            Text(status.message)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 36, height: 36)
                        .background(AppColors.surfaceElevated.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("profile.notice.close")
            }
        }
        .padding(AppSpacing.md)
        .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(status.tint.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
