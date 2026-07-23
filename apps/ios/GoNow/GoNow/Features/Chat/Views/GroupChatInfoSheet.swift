import PhotosUI
import SwiftUI

struct GroupChatInfoSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let conversationID: UUID
    var onConversationUpdated: (Conversation) -> Void = { _ in }

    @State private var details: ConversationDetails?
    @State private var avatarData = Data()
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var query = ""
    @State private var people: [SocialUser] = []
    @State private var addingIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var canManageMembers: Bool {
        details?.conversation.kind == "group"
            && details?.conversation.createdById == appState.currentUser?.id
    }

    private var availablePeople: [SocialUser] {
        let memberIDs = Set(details?.members.map(\.id) ?? [])
        return people.filter { !memberIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        content
                    }
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .navigationTitle("О чате")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task { await load() }
            .task(id: query) { await loadPeople() }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await uploadAvatar(item) }
            }
            .alert("Не удалось выполнить действие", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Попробуйте снова.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && details == nil {
            ProgressView("Загружаем информацию…")
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
        } else if let details {
            chatHeader(details.conversation)
            memberSection(details.members)
            if canManageMembers { addMemberSection }
        } else {
            AppEmptyState(
                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                title: "Не удалось открыть чат",
                message: errorMessage ?? "Проверьте подключение и попробуйте снова.",
                actionTitle: "Повторить"
            ) {
                Task { await load() }
            }
        }
    }

    private func chatHeader(_ conversation: Conversation) -> some View {
        GlassCard {
            VStack(spacing: AppSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(initials: conversation.title.initials, size: 88, imageData: avatarData)
                    if conversation.createdById == appState.currentUser?.id {
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            ZStack {
                                Circle().fill(AppColors.accentPrimary)
                                if isUploadingAvatar {
                                    ProgressView().tint(AppColors.textOnAccent)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .foregroundStyle(AppColors.textOnAccent)
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                        .disabled(isUploadingAvatar)
                        .accessibilityLabel("Изменить фотографию чата")
                    }
                }
                Text(conversation.title)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Label(
                    "\(conversation.memberCount) \(memberWord(conversation.memberCount))",
                    systemImage: conversation.kind == "activity" ? "figure.walk.motion" : "person.3.fill"
                )
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: conversation.avatarPath) {
            guard let path = conversation.avatarPath else {
                avatarData = Data()
                return
            }
            avatarData = (try? await appState.socialRepository.content(path: path)) ?? Data()
        }
    }

    private func memberSection(_ members: [ConversationMember]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Участники")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(members) { member in
                    if member.id == appState.currentUser?.id {
                        ConversationMemberCard(member: member)
                    } else {
                        NavigationLink {
                            PublicUserProfileView(
                                userID: member.id,
                                displayName: member.displayName,
                                avatarPath: member.avatarPath
                            )
                        } label: {
                            ConversationMemberCard(member: member)
                        }
                        .buttonStyle(AppPressButtonStyle())
                    }
                }
            }
        }
    }

    private var addMemberSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Добавить людей")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("Имя или @username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(.leading, AppSpacing.md)
            .frame(minHeight: 52)
            .glassSurface(.regular, cornerRadius: AppRadius.control)

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentPrimary)
            }

            ForEach(availablePeople.prefix(12)) { user in
                HStack(spacing: AppSpacing.md) {
                    SocialAvatar(user: user, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(user.isFriend ? "Друг · добавится сразу" : "Получит приглашение")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button { add(user) } label: {
                        if addingIDs.contains(user.id) {
                            ProgressView().frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "person.badge.plus")
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .disabled(addingIDs.contains(user.id))
                    .accessibilityLabel("Добавить \(user.displayName)")
                }
                .padding(AppSpacing.sm)
                .glassSurface(.regular, cornerRadius: AppRadius.card)
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await appState.socialRepository.conversationDetails(conversationID)
            details = loaded
            errorMessage = nil
            await loadPeople()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadPeople() async {
        guard canManageMembers else { return }
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        do {
            people = try await appState.socialRepository.people(query: query)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            guard let source = try await item.loadTransferable(type: Data.self) else { return }
            let data = try await MediaCompressionService().optimizeImage(
                source,
                maxDimension: 1_024,
                compressionQuality: 0.82
            )
            let conversation = try await appState.socialRepository.uploadConversationAvatar(
                conversationID,
                data: data
            )
            if let current = details {
                details = ConversationDetails(conversation: conversation, members: current.members)
            }
            avatarData = data
            onConversationUpdated(conversation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ user: SocialUser) {
        guard addingIDs.insert(user.id).inserted else { return }
        statusMessage = nil
        Task {
            defer { addingIDs.remove(user.id) }
            do {
                let result = try await appState.socialRepository.addConversationMember(
                    user.id,
                    conversationID: conversationID
                )
                statusMessage = result.status == "added"
                    ? "\(user.displayName) добавлен(а) в чат"
                    : "Приглашение для \(user.displayName) отправлено"
                people.removeAll { $0.id == user.id }
                if result.status == "added" { await load() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func memberWord(_ count: Int) -> String {
        let lastTwo = count % 100
        if (11...14).contains(lastTwo) { return "участников" }
        switch count % 10 {
        case 1: return "участник"
        case 2...4: return "участника"
        default: return "участников"
        }
    }
}

private struct ConversationMemberCard: View {
    @EnvironmentObject private var appState: AppState
    let member: ConversationMember
    @State private var imageData = Data()

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(initials: member.displayName.initials, size: 50, imageData: imageData)
                if member.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppColors.surfacePrimary, lineWidth: 3))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    if member.isCreator {
                        Text("Создатель")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accentPrimary)
                    }
                }
                Text(member.presenceText)
                    .font(AppTypography.caption)
                    .foregroundStyle(member.isOnline ? AppColors.accentPrimary : AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            if member.id != appState.currentUser?.id {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(AppSpacing.md)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
        .task(id: member.avatarPath) {
            guard let path = member.avatarPath else { return }
            imageData = (try? await appState.socialRepository.content(path: path)) ?? Data()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [member.displayName, member.isCreator ? "создатель" : nil, member.presenceText]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}
