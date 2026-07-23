import PhotosUI
import SwiftUI

struct CreateGroupChatSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Conversation) -> Void

    @State private var title = ""
    @State private var query = ""
    @State private var people: [SocialUser] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        chatIdentity
                        memberSearch
                        memberList
                    }
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Создаём…" : "Создать") { create() }
                        .disabled(isCreating || !(2...70).contains(trimmedTitle.count))
                }
            }
            .task(id: query) { await loadPeople() }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await preparePhoto(item) }
            }
            .alert("Не удалось создать группу", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var chatIdentity: some View {
        GlassCard {
            HStack(spacing: AppSpacing.md) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    ZStack {
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(AppColors.accentPrimary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .background(AppColors.surfaceSecondary, in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.borderSubtle, lineWidth: 1))
                }
                .accessibilityLabel("Выбрать фотографию группы")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Название")
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("Например, Поход в субботу", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: title) { _, value in
                            if value.count > 70 { title = String(value.prefix(70)) }
                        }
                }
            }
        }
    }

    private var memberSearch: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Участники")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("\(selectedIDs.count) выбрано")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
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
        }
    }

    @ViewBuilder
    private var memberList: some View {
        if isLoading && people.isEmpty {
            ProgressView("Загружаем людей…")
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.lg)
        } else if people.isEmpty {
            AppEmptyState(
                symbol: "person.2.slash",
                title: "Никого не найдено",
                message: "Измените запрос или добавьте друзей позже."
            )
        } else {
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(people) { user in
                    Button { toggle(user.id) } label: {
                        HStack(spacing: AppSpacing.md) {
                            SocialAvatar(user: user, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName)
                                    .font(AppTypography.bodyMedium)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(user.isFriend ? "Друг · добавится сразу" : "Получит приглашение")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(user.isFriend ? AppColors.accentPrimary : AppColors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: selectedIDs.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(selectedIDs.contains(user.id) ? AppColors.accentPrimary : AppColors.textMuted)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .glassSurface(.regular, cornerRadius: AppRadius.card)
                    }
                    .buttonStyle(AppPressButtonStyle())
                    .accessibilityLabel("\(user.displayName), \(user.isFriend ? "друг" : "получит приглашение")")
                    .accessibilityValue(selectedIDs.contains(user.id) ? "выбран" : "не выбран")
                }
            }
        }
    }

    private func toggle(_ userID: UUID) {
        if !selectedIDs.insert(userID).inserted { selectedIDs.remove(userID) }
    }

    private func loadPeople() async {
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do { people = try await appState.socialRepository.people(query: query) }
        catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }

    private func preparePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let source = try await item.loadTransferable(type: Data.self) else { return }
            photoData = try await MediaCompressionService().optimizeImage(
                source,
                maxDimension: 1_024,
                compressionQuality: 0.82
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() {
        guard (2...70).contains(trimmedTitle.count) else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                var conversation = try await appState.socialRepository.createGroup(
                    title: trimmedTitle,
                    memberIDs: Array(selectedIDs)
                )
                if let photoData {
                    conversation = try await appState.socialRepository.uploadConversationAvatar(
                        conversation.id,
                        data: photoData
                    )
                }
                onCreated(conversation)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
