import SwiftUI
import UIKit
import UserNotifications

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @State private var notifications: [GoNowNotification] = []
    @State private var filter: NotificationFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSettingsPresented = false
    @State private var path: [NotificationDestination] = []
    @State private var processingActionIDs: Set<UUID> = []
    @State private var resolvedActionIDs: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AuthBackdrop()
                if isLoading && notifications.isEmpty {
                    ProgressView("Загружаем уведомления…")
                } else if filteredNotifications.isEmpty {
                    AppEmptyState(
                        symbol: filter == .unread ? "checkmark.circle" : "bell.slash",
                        title: filter == .unread ? "Всё прочитано" : "Пока тихо",
                        message: emptyMessage,
                        actionTitle: errorMessage == nil ? nil : "Повторить",
                        action: errorMessage == nil ? nil : { Task { await load() } }
                    )
                } else {
                    notificationList
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { filterBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Настройки", systemImage: "slider.horizontal.3") {
                        isSettingsPresented = true
                    }
                }
            }
            .navigationDestination(for: NotificationDestination.self) { destination in
                switch destination {
                case .conversation(let id, let title):
                    ChatConversationView(conversationID: id, title: title)
                case .activity(let id):
                    ActivityDetailView(activityID: id, repository: appState.activityRepository)
                case .social:
                    SocialHubView()
                }
            }
        }
        .task(id: filter) {
            openPendingPushIfNeeded()
            await load()
        }
        .onChange(of: pushNotifications.pendingDestination) { _, _ in
            openPendingPushIfNeeded()
        }
        .onChange(of: appState.unreadNotificationCount) { _, _ in
            Task { await load(silently: true) }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NotificationSettingsView()
        }
        .alert("Не удалось обновить уведомления", isPresented: Binding(
            get: { errorMessage != nil && !filteredNotifications.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await load() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var notificationList: some View {
        List {
            ForEach(groupedNotifications, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { notification in
                        NotificationRow(
                            notification: notification,
                            isProcessing: processingActionIDs.contains(notification.id),
                            showsQuickActions: notification.quickAction != nil
                                && !resolvedActionIDs.contains(notification.id),
                            open: { open(notification) },
                            accept: { performAction(notification, decision: .accept) },
                            decline: { performAction(notification, decision: .decline) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await delete(notification) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !notification.isRead {
                                Button {
                                    Task { await markRead(notification) }
                                } label: {
                                    Label("Прочитано", systemImage: "checkmark")
                                }
                                .tint(AppColors.success)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(AppColors.divider)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load(silently: true) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(NotificationFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(AppTypography.captionStrong)
                            .foregroundStyle(filter == item ? AppColors.textOnAccent : AppColors.textPrimary)
                            .padding(.horizontal, AppSpacing.md)
                            .frame(minHeight: AppLayout.minimumTouchTarget)
                            .background(filter == item ? AnyShapeStyle(AppGradients.brand) : AnyShapeStyle(.regularMaterial), in: Capsule())
                            .overlay { Capsule().strokeBorder(AppColors.glassBorder.opacity(0.5), lineWidth: 1) }
                    }
                    .buttonStyle(AppPressButtonStyle())
                }
            }
            .padding(.horizontal, AppLayout.horizontalInset)
            .padding(.vertical, AppSpacing.xs)
        }
        .background(.ultraThinMaterial)
    }

    private var filteredNotifications: [GoNowNotification] {
        switch filter {
        case .all: notifications
        case .unread: notifications.filter { !$0.isRead }
        case .social: notifications.filter { $0.category == .social }
        case .activities: notifications.filter { $0.category == .activities }
        }
    }

    private var groupedNotifications: [(title: String, items: [GoNowNotification])] {
        let calendar = Calendar.autoupdatingCurrent
        let today = filteredNotifications.filter { calendar.isDateInToday($0.createdAt) }
        let earlier = filteredNotifications.filter { !calendar.isDateInToday($0.createdAt) }
        return [("Сегодня", today), ("Ранее", earlier)].filter { !$0.items.isEmpty }
    }

    private var emptyMessage: String {
        if let errorMessage { return errorMessage }
        switch filter {
        case .all: return "Здесь появятся заявки в друзья, приглашения и важные изменения активностей."
        case .unread: return "Новых уведомлений нет."
        default: return "В этой категории пока нет уведомлений."
        }
    }

    private func load(silently: Bool = false) async {
        if !silently { isLoading = true }
        defer { isLoading = false }
        do {
            let feed = try await appState.notificationRepository.list()
            notifications = feed.items
            if feed.unreadCount > 0 {
                let count = try await appState.notificationRepository.markAllRead()
                notifications = notifications.map { item in
                    var item = item
                    item.isRead = true
                    return item
                }
                appState.applyUnreadNotificationCount(count)
            } else {
                appState.applyUnreadNotificationCount(0)
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ notification: GoNowNotification) {
        if let destination = notification.destination {
            path.append(destination)
        }
        guard !notification.isRead else { return }
        Task { await markRead(notification) }
    }

    private func openPendingPushIfNeeded() {
        guard let destination = pushNotifications.pendingDestination else { return }
        path.append(destination)
        pushNotifications.consumePendingDestination()
    }

    private func markRead(_ notification: GoNowNotification) async {
        do {
            let updated = try await appState.notificationRepository.markRead(notification.id)
            if let index = notifications.firstIndex(where: { $0.id == updated.id }) {
                notifications[index] = updated
            }
            await appState.reloadNotificationCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAction(
        _ notification: GoNowNotification,
        decision: NotificationDecision
    ) {
        guard let action = notification.quickAction,
              !processingActionIDs.contains(notification.id) else { return }
        Task {
            processingActionIDs.insert(notification.id)
            defer { processingActionIDs.remove(notification.id) }
            do {
                switch action {
                case .friendRequest(let userID):
                    _ = try await appState.socialRepository.decideFriend(
                        userID,
                        action: decision.rawValue
                    )
                case .invitation(let invitationID):
                    _ = try await appState.socialRepository.decideInvitation(
                        invitationID,
                        action: decision.rawValue
                    )
                case .activityApplication(let activityID, let applicationID):
                    _ = try await appState.activityRepository.updateApplication(
                        activityID: activityID,
                        applicationID: applicationID,
                        status: decision == .accept ? .accepted : .rejected
                    )
                }
                resolvedActionIDs.insert(notification.id)
                await appState.reloadNotificationCount()
                await appState.reloadChatUnreadCount()
                AppHaptics.confirmation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ notification: GoNowNotification) async {
        do {
            try await appState.notificationRepository.delete(notification.id)
            notifications.removeAll { $0.id == notification.id }
            await appState.reloadNotificationCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum NotificationDecision: String {
    case accept
    case decline
}

private enum NotificationQuickAction {
    case friendRequest(UUID)
    case invitation(UUID)
    case activityApplication(activityID: UUID, applicationID: UUID)
}

private extension GoNowNotification {
    var quickAction: NotificationQuickAction? {
        switch kind {
        case "friend_request":
            guard payload.status == nil || payload.status == "pending",
                  let entityId else { return nil }
            return .friendRequest(entityId)
        case "invitation":
            guard payload.status == nil || payload.status == "pending",
                  let entityId else { return nil }
            return .invitation(entityId)
        case "activity_application":
            guard payload.status == "pending",
                  let entityId,
                  let applicationID = payload.applicationId else { return nil }
            return .activityApplication(activityID: entityId, applicationID: applicationID)
        default:
            return nil
        }
    }
}

private struct NotificationRow: View {
    let notification: GoNowNotification
    let isProcessing: Bool
    let showsQuickActions: Bool
    let open: () -> Void
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button(action: open) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    categoryIcon
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(notification.title)
                            .font(.body.weight(notification.isRead ? .medium : .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(notification.body)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(notification.createdAt, format: .relative(presentation: .named))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                    }
                    Spacer(minLength: 0)
                    if notification.destination != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textMuted)
                            .frame(width: 24, height: 44)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsQuickActions {
                HStack(spacing: AppSpacing.sm) {
                    Button(action: accept) {
                        Group {
                            if isProcessing {
                                ProgressView().tint(AppColors.textOnAccent)
                            } else {
                                Label("Принять", systemImage: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .clipShape(Capsule())
                    .disabled(isProcessing)

                    Button(role: .destructive, action: decline) {
                        Label("Отклонить", systemImage: "xmark")
                            .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                    }
                    .buttonStyle(GlassSecondaryButtonStyle(isDestructive: true))
                    .clipShape(Capsule())
                    .disabled(isProcessing)
                }
                .padding(.leading, 48 + AppSpacing.md)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var categoryIcon: some View {
        ZStack {
            Circle().fill(categoryColor.opacity(0.16))
            Image(systemName: notification.category.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(categoryColor)
        }
        .frame(width: 48, height: 48)
        .overlay(alignment: .topTrailing) {
            if !notification.isRead {
                Circle()
                    .fill(AppColors.accentSecondary)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(AppColors.surfacePrimary, lineWidth: 2) }
            }
        }
        .accessibilityHidden(true)
    }

    private var categoryColor: Color {
        switch notification.category {
        case .social: AppColors.accentSecondary
        case .messages: AppColors.locationAccent
        case .activities: AppColors.success
        case .system: AppColors.warning
        }
    }
}

private enum NotificationFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case social
    case activities

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все"
        case .unread: "Новые"
        case .social: "Люди"
        case .activities: "Активности"
        }
    }
    var symbol: String {
        switch self {
        case .all: "bell"
        case .unread: "circle.fill"
        case .social: "person.2"
        case .activities: "figure.run"
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @State private var preferences = NotificationPreferences(
        pushEnabled: true,
        friendRequests: true,
        messages: true,
        invitations: true,
        activities: true,
        soundEnabled: true
    )
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Разрешение iPhone", systemImage: permissionSymbol)
                        Spacer()
                        Text(permissionTitle)
                            .foregroundStyle(permissionColor)
                    }
                    if pushNotifications.authorizationStatus == .denied {
                        Button("Открыть настройки iPhone") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else if pushNotifications.authorizationStatus == .notDetermined {
                        Button("Разрешить push-уведомления") {
                            Task { await pushNotifications.requestAuthorizationIfNeeded() }
                        }
                    }
                } footer: {
                    Text("Внутренняя лента GoNow работает независимо от системного разрешения iPhone.")
                }

                Section("Push-уведомления") {
                    Toggle("Все push-уведомления", isOn: $preferences.pushEnabled)
                        .disabled(isLoading)
                    Group {
                        Toggle("Заявки в друзья", isOn: $preferences.friendRequests)
                        Toggle("Сообщения", isOn: $preferences.messages)
                        Toggle("Приглашения на прогулку", isOn: $preferences.invitations)
                        Toggle("Активности и напоминания", isOn: $preferences.activities)
                        Toggle("Звук", isOn: $preferences.soundEnabled)
                    }
                    .disabled(!preferences.pushEnabled || isLoading)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuthBackdrop() }
            .navigationTitle("Настройки уведомлений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(isLoading || isSaving)
                }
            }
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
    }

    private var permissionTitle: String {
        switch pushNotifications.authorizationStatus {
        case .authorized: "Разрешены"
        case .provisional: "Тихо"
        case .ephemeral: "Временно"
        case .denied: "Запрещены"
        case .notDetermined: "Не настроены"
        @unknown default: "Неизвестно"
        }
    }

    private var permissionSymbol: String {
        pushNotifications.authorizationStatus == .denied ? "bell.slash.fill" : "bell.badge.fill"
    }

    private var permissionColor: Color {
        pushNotifications.authorizationStatus == .denied ? AppColors.error : AppColors.success
    }

    private func load() async {
        defer { isLoading = false }
        await pushNotifications.refreshAuthorizationStatus()
        do {
            preferences = try await appState.notificationRepository.preferences()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if preferences.pushEnabled {
            await pushNotifications.requestAuthorizationIfNeeded()
        }
        do {
            preferences = try await appState.notificationRepository.updatePreferences(preferences)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
