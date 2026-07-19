import SwiftUI
import UIKit

struct ChatTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var conversations: [Conversation] = []
    @State private var invitations: [MeetingInvitation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var pendingInvitations: [MeetingInvitation] {
        invitations.filter { $0.isIncoming && $0.status == "pending" }
    }

    var body: some View {
        NavigationStack {
            GlassScreen {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack {
                        Text("Чаты")
                            .font(AppTypography.screenTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        NavigationLink {
                            SocialHubView()
                        } label: {
                            Image(systemName: "person.2.fill")
                                .frame(width: 44, height: 44)
                                .glassSurface(.subtle, cornerRadius: 22)
                        }
                        .accessibilityLabel("Друзья и приглашения")
                    }

                    if !pendingInvitations.isEmpty {
                        NavigationLink {
                            SocialHubView(initialSection: .invitations)
                        } label: {
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

                    if isLoading && conversations.isEmpty {
                        ProgressView("Загружаем чаты…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if conversations.isEmpty {
                        AppEmptyState(
                            symbol: "bubble.left.and.bubble.right",
                            title: "Пока нет чатов",
                            message: "Найдите человека, напишите ему или примите приглашение на встречу."
                        )
                        NavigationLink("Найти людей") {
                            SocialHubView(initialSection: .people)
                        }
                            .buttonStyle(GradientPrimaryButtonStyle())
                    } else {
                        LazyVStack(spacing: AppSpacing.sm) {
                            ForEach(conversations) { conversation in
                                NavigationLink {
                                    ChatConversationView(conversationID: conversation.id, title: conversation.title)
                                } label: {
                                    ConversationRow(conversation: conversation)
                                }
                                .buttonStyle(AppPressButtonStyle())
                            }
                        }
                    }
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .alert("Не удалось загрузить чаты", isPresented: Binding(
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

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let conversationsTask = appState.socialRepository.conversations()
            async let invitationsTask = appState.socialRepository.invitations()
            let result = try await (conversationsTask, invitationsTask)
            conversations = result.0
            invitations = result.1
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ConversationRow: View {
    @EnvironmentObject private var appState: AppState
    let conversation: Conversation
    @State private var imageData = Data()

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ProfileAvatar(initials: conversation.title.initials, size: 56, imageData: imageData)
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
                    Text(conversation.lastMessage ?? (conversation.kind == "meeting" ? "Обсудите место и время" : "Начните диалог"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
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
            guard let path = conversation.avatarPath else { return }
            imageData = (try? await appState.socialRepository.content(path: path)) ?? Data()
        }
    }
}
