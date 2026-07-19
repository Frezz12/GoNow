import SwiftUI
import UIKit

struct SocialHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var section: SocialHubSection
    @State private var people: [SocialUser] = []
    @State private var invitations: [MeetingInvitation] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var invitee: SocialUser?
    @State private var chatTarget: ChatTarget?

    init(initialSection: SocialHubSection = .friends) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        GlassScreen {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Picker("Раздел", selection: $section) {
                    ForEach(SocialHubSection.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch section {
                case .people:
                    peopleContent
                case .friends:
                    userList(people.filter(\.isFriend), emptyTitle: "Список друзей пуст")
                case .invitations:
                    invitationContent
                }
            }
        }
        .navigationTitle("Друзья и встречи")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reloadAll() }
        .task(id: query) {
            guard section == .people else { return }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await loadPeople()
        }
        .refreshable { await reloadAll() }
        .sheet(item: $invitee) { user in
            InviteWalkSheet(user: user) {
                invitee = nil
                await loadInvitations()
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
        .navigationDestination(item: $chatTarget) { target in
            ChatConversationView(conversationID: target.id, title: target.title)
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var peopleContent: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("Имя, @username или город", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: 52)
            .glassSurface(.regular, cornerRadius: AppRadius.control)

            userList(people, emptyTitle: query.isEmpty ? "Пока некого показать" : "Никого не найдено")
        }
    }

    @ViewBuilder
    private func userList(_ users: [SocialUser], emptyTitle: String) -> some View {
        if isLoading && users.isEmpty {
            ProgressView("Загружаем людей…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if users.isEmpty {
            GlassCard {
                AppEmptyState(
                    symbol: "person.2.slash",
                    title: emptyTitle,
                    message: "Профили и новые заявки появятся здесь."
                )
            }
        } else {
            ForEach(users) { user in
                SocialUserCard(
                    user: user,
                    friendAction: { friendAction(user) },
                    messageAction: { startChat(user) },
                    inviteAction: { invitee = user }
                )
            }
        }
    }

    private var invitationContent: some View {
        VStack(spacing: AppSpacing.md) {
            if invitations.isEmpty {
                GlassCard {
                    AppEmptyState(
                        symbol: "figure.walk.motion",
                        title: "Нет приглашений",
                        message: "Позовите друга на прогулку, кофе или другое совместное занятие."
                    )
                }
            } else {
                ForEach(invitations) { invitation in
                    InvitationCard(
                        invitation: invitation,
                        accept: { decideInvitation(invitation, action: "accept") },
                        counter: { decideInvitation(invitation, action: "counter") },
                        decline: { decideInvitation(invitation, action: "decline") },
                        openChat: {
                            if let id = invitation.conversationId {
                                chatTarget = ChatTarget(id: id, title: invitation.templateTitle)
                            }
                        }
                    )
                }
            }
        }
    }

    private func reloadAll() async {
        async let peopleTask: Void = loadPeople()
        async let invitationsTask: Void = loadInvitations()
        _ = await (peopleTask, invitationsTask)
    }

    private func loadPeople() async {
        isLoading = true
        defer { isLoading = false }
        do { people = try await appState.socialRepository.people(query: query) }
        catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadInvitations() async {
        do { invitations = try await appState.socialRepository.invitations() }
        catch { errorMessage = error.localizedDescription }
    }

    private func friendAction(_ user: SocialUser) {
        Task {
            do {
                if user.isFriend {
                    try await appState.socialRepository.removeFriend(user.id)
                } else if user.isIncomingRequest {
                    _ = try await appState.socialRepository.decideFriend(user.id, action: "accept")
                } else if !user.hasPendingRequest {
                    _ = try await appState.socialRepository.requestFriend(user.id)
                }
                await loadPeople()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func startChat(_ user: SocialUser) {
        Task {
            do {
                let conversation = try await appState.socialRepository.createConversation(with: user.id)
                chatTarget = ChatTarget(id: conversation.id, title: conversation.title)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func decideInvitation(_ invitation: MeetingInvitation, action: String) {
        Task {
            do {
                let updated = try await appState.socialRepository.decideInvitation(invitation.id, action: action)
                await loadInvitations()
                if action == "accept", let id = updated.conversationId {
                    chatTarget = ChatTarget(id: id, title: updated.templateTitle)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

enum SocialHubSection: String, CaseIterable, Identifiable {
    case friends, people, invitations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .people: "Люди"
        case .friends: "Друзья"
        case .invitations: "Встречи"
        }
    }
    var symbol: String {
        switch self {
        case .people: "magnifyingglass"
        case .friends: "person.2.fill"
        case .invitations: "figure.walk.motion"
        }
    }
}

private struct ChatTarget: Identifiable, Hashable {
    let id: UUID
    let title: String
}

private struct SocialUserCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let user: SocialUser
    let friendAction: () -> Void
    let messageAction: () -> Void
    let inviteAction: () -> Void
    @State private var isAboutExpanded = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    SocialAvatar(user: user, size: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(user.displayName)
                            .font(AppTypography.cardTitle)
                        Text("@\(user.username)")
                            .font(AppTypography.captionStrong)
                            .foregroundStyle(AppColors.accentPrimary)
                            .textSelection(.enabled)
                            .accessibilityLabel("Username: \(user.username)")
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                        isAboutExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label(isAboutExpanded ? "Скрыть информацию" : "О человеке", systemImage: "person.text.rectangle")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isAboutExpanded ? 180 : 0))
                    }
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isAboutExpanded ? "Сворачивает данные человека" : "Показывает данные человека")

                if isAboutExpanded {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if (user.city?.isEmpty != false) && (user.bio?.isEmpty != false) && user.interests.isEmpty {
                            Label("Информация пока не заполнена", systemImage: "info.circle")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        if let city = user.city, !city.isEmpty {
                            Label(city, systemImage: "mappin.and.ellipse")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !user.interests.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(user.interests.prefix(5), id: \.self) { interest in
                                    Text(interest)
                                        .font(AppTypography.badge)
                                        .foregroundStyle(AppColors.accentPrimary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(AppColors.accentPrimary.opacity(0.11), in: Capsule())
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: AppSpacing.sm) {
                    Button(action: friendAction) {
                        Label(friendTitle, systemImage: friendSymbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(GlassSecondaryButtonStyle(isDestructive: user.isFriend))
                    .disabled(user.hasPendingRequest && !user.isIncomingRequest)

                    if user.canMessage {
                        Button(action: messageAction) {
                            Image(systemName: "message.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(GlassInlineButtonStyle())
                        .accessibilityLabel("Написать")
                    }

                    if user.canInvite {
                        Button(action: inviteAction) {
                            Image(systemName: "figure.walk.motion")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(GlassInlineButtonStyle())
                        .accessibilityLabel("Пригласить на прогулку")
                    }
                }
            }
        }
    }

    private var friendTitle: String {
        if user.isFriend { return "Удалить" }
        if user.isIncomingRequest { return "Принять" }
        if user.hasPendingRequest { return "Отправлено" }
        return "В друзья"
    }
    private var friendSymbol: String {
        if user.isFriend { return "person.badge.minus" }
        if user.isIncomingRequest { return "person.badge.checkmark" }
        return "person.badge.plus"
    }
}

struct SocialAvatar: View {
    @EnvironmentObject private var appState: AppState
    let user: SocialUser
    let size: CGFloat
    @State private var data = Data()

    var body: some View {
        ProfileAvatar(initials: user.initials, size: size, imageData: data)
            .task(id: user.avatarPath) {
                guard let path = user.avatarPath else { return }
                data = (try? await appState.socialRepository.content(path: path)) ?? Data()
            }
    }
}

private struct InvitationCard: View {
    let invitation: MeetingInvitation
    let accept: () -> Void
    let counter: () -> Void
    let decline: () -> Void
    let openChat: () -> Void

    var body: some View {
        GlassCard(style: invitation.status == "pending" ? .prominent : .regular) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Image(systemName: MeetingTemplate(rawValue: invitation.template)?.symbol ?? "figure.walk")
                        .font(.title2)
                        .foregroundStyle(AppColors.accentPrimary)
                        .frame(width: 48, height: 48)
                        .background(AppColors.accentPrimary.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invitation.templateTitle)
                            .font(AppTypography.cardTitle)
                        Text(invitation.isIncoming ? "От \(invitation.senderName)" : "Для \(invitation.recipientName)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Text(invitation.status == "pending" ? "Ожидает" : statusTitle)
                        .font(AppTypography.badge)
                        .foregroundStyle(invitation.status == "accepted" ? AppColors.success : AppColors.textSecondary)
                }
                if let date = invitation.proposedAt {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(AppTypography.body)
                }
                if let place = invitation.place, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(AppTypography.body)
                }
                if let message = invitation.message, !message.isEmpty {
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                if invitation.isIncoming && invitation.status == "pending" {
                    VStack(spacing: AppSpacing.sm) {
                        Button("Принять", action: accept)
                            .buttonStyle(GradientPrimaryButtonStyle())
                        HStack {
                            Button("Другое время / место", action: counter)
                            Spacer()
                            Button("Отклонить", role: .destructive, action: decline)
                        }
                        .font(AppTypography.captionStrong)
                    }
                } else if invitation.status == "accepted", invitation.conversationId != nil {
                    Button("Открыть чат", action: openChat)
                        .buttonStyle(GlassSecondaryButtonStyle())
                }
            }
        }
    }

    private var statusTitle: String {
        switch invitation.status {
        case "accepted": "Принято"
        case "declined": "Отклонено"
        case "expired": "Истекло"
        case "countered": "Нужны изменения"
        default: invitation.status
        }
    }
}

private struct InviteWalkSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let user: SocialUser
    let completed: () async -> Void
    @State private var template: MeetingTemplate = .walk
    @State private var hasDate = true
    @State private var proposedAt = Date.now.addingTimeInterval(7_200)
    @State private var place = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Чем хотите заняться?")
                        .font(AppTypography.sectionTitle)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
                        ForEach(MeetingTemplate.allCases) { item in
                            Button { template = item } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: item.symbol)
                                        .font(.title3)
                                    Text(item.title)
                                        .font(AppTypography.badge)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(template == item ? AppColors.textOnAccent : AppColors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 78)
                                .background(template == item ? AnyShapeStyle(AppGradients.brand) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Toggle("Предложить дату и время", isOn: $hasDate)
                        .font(AppTypography.bodyMedium)
                    if hasDate {
                        DatePicker("Когда", selection: $proposedAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    }

                    AppTextField(title: "Где", text: $place, prompt: "Можно решить позже")
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Сообщение")
                            .font(AppTypography.captionStrong)
                            .foregroundStyle(AppColors.textSecondary)
                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .padding(AppSpacing.sm)
                            .glassSurface(.regular, cornerRadius: AppRadius.control)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.error)
                    }

                    Button {
                        send()
                    } label: {
                        Label(isSending ? "Отправляем…" : "Пригласить \(user.displayName)", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .disabled(isSending)
                }
                .padding(AppLayout.horizontalInset)
            }
            .navigationTitle("Пригласить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func send() {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                _ = try await appState.socialRepository.createInvitation(CreateInvitationDraft(
                    recipientId: user.id,
                    template: template,
                    proposedAt: hasDate ? proposedAt : nil,
                    place: place.nonEmpty,
                    message: message.nonEmpty
                ))
                await completed()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
