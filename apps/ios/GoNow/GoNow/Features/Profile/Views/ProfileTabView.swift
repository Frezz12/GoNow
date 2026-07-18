import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct ProfileTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isEditing = false
    @State private var isSettingsPresented = false
    @State private var isGalleryExpanded = false
    @State private var isProfileSetupPresented = false

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
                                if let birthDateAndAgeText = user.birthDateAndAgeText {
                                    Label(birthDateAndAgeText, systemImage: "calendar")
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                if let locationText = user.profileLocationText {
                                    Label(locationText, systemImage: "mappin.and.ellipse")
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .lineLimit(1)
                                        .accessibilityLabel(L10n.format("profile.location.accessibility %@", locationText))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)

                        GlassCard {
                            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    HStack {
                                        Text("profile.photos.title")
                                            .font(AppTypography.sectionTitle)
                                        Spacer(minLength: 8)
                                        Button {
                                            withAnimation(accessibilityReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                                                isGalleryExpanded.toggle()
                                            }
                                        } label: {
                                            Label(
                                                isGalleryExpanded ? "profile.photos.collapse" : "profile.photos.show_all",
                                                systemImage: isGalleryExpanded ? "chevron.up" : "chevron.right"
                                            )
                                            .labelStyle(.titleAndIcon)
                                            .font(AppTypography.captionStrong)
                                            .foregroundStyle(AppColors.accentPrimary)
                                            .frame(minHeight: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(isGalleryExpanded ? L10n.string("profile.photos.collapse.accessibility") : L10n.string("profile.photos.show_all.accessibility"))
                                    }
                                    ProfilePhotoGallery(isExpanded: $isGalleryExpanded)
                                }

                                ProfileDetailsGrid(user: user)

                                if let bio = user.bio?.nonEmpty {
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        Label("profile.bio.title", systemImage: "person.text.rectangle")
                                            .font(AppTypography.captionStrong)
                                            .foregroundStyle(AppColors.accentPrimary)
                                        Text(bio)
                                            .font(AppTypography.body)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }

                                if let interests = user.interests, !interests.isEmpty {
                                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                        Label("profile.interests.title", systemImage: "tag")
                                            .font(AppTypography.captionStrong)
                                            .foregroundStyle(AppColors.accentPrimary)
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                                            ForEach(interests, id: \.self) { interest in
                                                Text(interest)
                                                    .font(AppTypography.badge)
                                                    .padding(.horizontal, AppSpacing.sm)
                                                    .padding(.vertical, AppSpacing.xs)
                                                    .background(AppColors.accentPrimary.opacity(0.12), in: Capsule())
                                                    .foregroundStyle(AppColors.accentPrimary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    profileSettingsButton
                }
            }
            .navigationDestination(isPresented: $isSettingsPresented) {
                SettingsView()
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

private struct ProfileDetailsGrid: View {
    let user: CurrentUser

    var body: some View {
        let fields = [
            DetailField(icon: "briefcase.fill", title: L10n.string("profile.occupation.title"), value: user.occupation?.nonEmpty),
            DetailField(icon: "heart.text.square", title: L10n.string("profile.relationship.title"), value: user.relationshipStatus?.nonEmpty),
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
                            .lineLimit(2)
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
