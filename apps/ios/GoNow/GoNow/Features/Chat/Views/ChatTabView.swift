import SwiftUI

struct ChatTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var conversations: [Conversation] = []
    @State private var invitations: [MeetingInvitation] = []
    @State private var groupInvitations: [ConversationInvitation] = []
    @State private var section = ChatSection.personal
    @State private var showsArchive = false
    @State private var showsGroupCreator = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var pendingInvitations: [MeetingInvitation] {
        invitations.filter { $0.isIncoming && $0.status == "pending" }
    }

    private var visibleConversations: [Conversation] {
        conversations.filter { conversation in
            if showsArchive { return conversation.isArchived }
            guard !conversation.isArchived else { return false }
            return section == .groups ? conversation.isGroup : !conversation.isGroup
        }
    }

    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    header

                    if showsArchive {
                        Label("Архив", systemImage: "archivebox.fill")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Picker("Тип чатов", selection: $section) {
                            ForEach(ChatSection.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if !showsArchive, section == .personal, !pendingInvitations.isEmpty {
                        meetingInvitationBanner
                    }
                    if !showsArchive, section == .groups, !groupInvitations.isEmpty {
                        groupInvitationCards
                    }

                    content
                }
            }
            .refreshable { await reload() }
            .task {
                while !Task.isCancelled {
                    await reload()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .sheet(isPresented: $showsGroupCreator) {
                CreateGroupChatSheet { conversation in
                    conversations.insert(conversation, at: 0)
                    section = .groups
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .alert("Не удалось выполнить действие", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Повторить") { Task { await reload() } }
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("Чаты")
                .font(AppTypography.screenTitle)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Button {
                showsArchive.toggle()
            } label: {
                Image(systemName: showsArchive ? "arrow.uturn.backward" : "archivebox")
                    .frame(width: 44, height: 44)
                    .glassSurface(showsArchive ? .prominent : .subtle, cornerRadius: 22)
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel(showsArchive ? "Вернуться к чатам" : "Открыть архив")

            Button { showsGroupCreator = true } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .glassSurface(.subtle, cornerRadius: 22)
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel("Создать групповой чат")

            NavigationLink { SocialHubView() } label: {
                Image(systemName: "person.2.fill")
                    .frame(width: 44, height: 44)
                    .glassSurface(.subtle, cornerRadius: 22)
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel("Друзья и приглашения")
        }
    }

    private var meetingInvitationBanner: some View {
        NavigationLink { SocialHubView(initialSection: .invitations) } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "figure.walk.motion")
                    .font(.title2)
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 50, height: 50)
                    .background(AppGradients.brand, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Новые приглашения")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(pendingInvitations.count) ждут вашего ответа")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(AppSpacing.md)
            .glassSurface(.prominent, cornerRadius: AppRadius.card)
        }
        .buttonStyle(AppPressButtonStyle())
    }

    private var groupInvitationCards: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(groupInvitations) { invitation in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(AppColors.accentPrimary)
                        .frame(width: 44, height: 44)
                        .glassSurface(.subtle, cornerRadius: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invitation.conversationTitle)
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("\(invitation.inviterName) приглашает в чат")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button { decide(invitation, action: "decline") } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отклонить приглашение")
                    Button { decide(invitation, action: "accept") } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.textOnAccent)
                            .frame(width: 44, height: 44)
                            .background(AppColors.accentPrimary, in: Circle())
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .accessibilityLabel("Принять приглашение")
                }
                .padding(AppSpacing.sm)
                .glassSurface(.prominent, cornerRadius: AppRadius.card)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && conversations.isEmpty {
            ProgressView("Загружаем чаты…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if visibleConversations.isEmpty {
            AppEmptyState(
                symbol: showsArchive ? "archivebox" : (section == .groups ? "person.3" : "bubble.left.and.bubble.right"),
                title: showsArchive ? "Архив пуст" : (section == .groups ? "Пока нет групп" : "Пока нет личных чатов"),
                message: showsArchive
                    ? "Скрытые чаты появятся здесь."
                    : (section == .groups ? "Создайте группу или присоединитесь к активности." : "Найдите человека и начните разговор.")
            )
        } else {
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(visibleConversations) { conversation in
                    NavigationLink {
                        ChatConversationView(
                            conversationID: conversation.id,
                            title: conversation.title,
                            conversationKind: conversation.kind,
                            avatarPath: conversation.avatarPath,
                            presenceText: conversation.presenceText
                        )
                    } label: {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .swipeActions(edge: .trailing) {
                        Button {
                            archive(conversation, archived: !conversation.isArchived)
                        } label: {
                            Label(conversation.isArchived ? "Вернуть" : "В архив", systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
                        }
                        .tint(AppColors.accentPrimary)
                    }
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let conversationsTask = appState.socialRepository.conversations()
            async let invitationsTask = appState.socialRepository.invitations()
            async let groupInvitationsTask = appState.socialRepository.conversationInvitations()
            let result = try await (conversationsTask, invitationsTask, groupInvitationsTask)
            conversations = result.0
            invitations = result.1
            groupInvitations = result.2
            appState.applyUnreadChatCount(conversations.reduce(0) { $0 + max(0, $1.unreadCount) })
        } catch { errorMessage = error.localizedDescription }
    }

    private func archive(_ conversation: Conversation, archived: Bool) {
        Task {
            do {
                let updated = try await appState.socialRepository.archiveConversation(conversation.id, archived: archived)
                replace(updated)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func decide(_ invitation: ConversationInvitation, action: String) {
        Task {
            do {
                _ = try await appState.socialRepository.decideConversationInvitation(invitation.id, action: action)
                await reload()
                if action == "accept" { section = .groups }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func replace(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            conversations.insert(conversation, at: 0)
            return
        }
        conversations[index] = conversation
    }
}

private enum ChatSection: String, CaseIterable, Identifiable {
    case personal
    case groups

    var id: String { rawValue }
    var title: String { self == .personal ? "Личные" : "Группы" }
}

private struct ConversationRow: View {
    @EnvironmentObject private var appState: AppState
    let conversation: Conversation
    @State private var imageData = Data()

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(initials: conversation.title.initials, size: 56, imageData: imageData)
                if conversation.kind == "direct" && conversation.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(AppColors.surfacePrimary, lineWidth: 3))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(conversation.title)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let date = conversation.lastMessageAt {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.lastMessage ?? (conversation.isGroup ? "Начните обсуждение" : "Начните диалог"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        if let presence = conversation.presenceText {
                            Text(presence)
                                .font(.caption2)
                                .foregroundStyle(conversation.isOnline ? AppColors.accentPrimary : AppColors.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.textOnAccent)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(AppColors.accentPrimary, in: Capsule())
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
        .task(id: conversation.avatarPath) {
            guard let path = conversation.avatarPath else {
                imageData = Data()
                return
            }
            imageData = (try? await appState.socialRepository.content(path: path)) ?? Data()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [conversation.title, conversation.presenceText, conversation.lastMessage]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
