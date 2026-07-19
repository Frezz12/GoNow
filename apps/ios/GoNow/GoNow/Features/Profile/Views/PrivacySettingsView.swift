import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var messagePrivacy: SocialPrivacy = .everyone
    @State private var invitationPrivacy: SocialPrivacy = .everyone
    @State private var savedSettings: SocialPrivacySettings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    GlassCard(style: .prominent) {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("Личные границы", systemImage: "lock.shield.fill")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Настройки применяются ко всем профилям сразу. Друзья всегда могут продолжить уже созданный чат.")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Label("Кто может написать", systemImage: "message.fill")
                                .font(AppTypography.sectionTitle)
                            privacyPicker(selection: $messagePrivacy, includesVerified: false)
                            Text(messagePrivacyDescription)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Label("Кто может пригласить", systemImage: "figure.walk.motion")
                                .font(AppTypography.sectionTitle)
                            privacyPicker(selection: $invitationPrivacy, includesVerified: true)
                            Text("Одновременно между двумя людьми может быть только одно активное приглашение; действует лимит 10 приглашений в сутки.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Button {
                        save()
                    } label: {
                        Label(isSaving ? "Сохраняем…" : saveButtonTitle, systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .disabled(isSaving || !hasChanges)
                }
                .frame(maxWidth: AppLayout.maxContentWidth)
                .padding(.horizontal, AppLayout.horizontalInset)
                .padding(.vertical, AppSpacing.xl)
            }
        }
        .navigationTitle("Конфиденциальность")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView().controlSize(.large) } }
        .task { await load() }
        .alert("Не удалось сохранить", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func privacyPicker(selection: Binding<SocialPrivacy>, includesVerified: Bool) -> some View {
        Picker("Доступ", selection: selection) {
            ForEach(SocialPrivacy.allCases.filter { includesVerified || $0 != .verified }) { privacy in
                Text(privacy.title).tag(privacy)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .glassSurface(.subtle, cornerRadius: AppRadius.control)
    }

    private var messagePrivacyDescription: String {
        switch messagePrivacy {
        case .everyone: "Любой пользователь сможет открыть с вами новый чат."
        case .friends: "Кнопка сообщения появится только у ваших друзей."
        case .nobody: "Новые личные чаты будут закрыты."
        case .verified: ""
        }
    }

    private var hasChanges: Bool {
        savedSettings != SocialPrivacySettings(
            messagePrivacy: messagePrivacy,
            invitationPrivacy: invitationPrivacy
        )
    }

    private var saveButtonTitle: String { hasChanges ? "Сохранить" : "Сохранено" }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let settings = try await appState.socialRepository.privacy()
            messagePrivacy = settings.messagePrivacy
            invitationPrivacy = settings.invitationPrivacy
            savedSettings = settings
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                savedSettings = try await appState.socialRepository.updatePrivacy(
                    message: messagePrivacy,
                    invitation: invitationPrivacy
                )
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
