import SwiftUI

struct PublicUserProfileView: View {
    @EnvironmentObject private var appState: AppState
    let userID: UUID
    let displayName: String
    let avatarPath: String?
    @State private var profile: PublicUserProfile?
    @State private var photos: [ProfilePhoto] = []
    @State private var avatarData = Data()
    @State private var selectedPhoto: ProfilePhoto?
    @State private var likingPhotoIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(user: SocialUser) {
        userID = user.id
        displayName = user.displayName
        avatarPath = user.avatarPath
    }

    init(userID: UUID, displayName: String, avatarPath: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarPath = avatarPath
    }

    var body: some View {
        GlassScreen {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if isLoading && profile == nil {
                    ProgressView("Загружаем профиль…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 96)
                } else if let profile {
                    profileHeader(profile)
                    aboutCard(profile)
                    photoGallery(profile)
                    posts(profile)
                } else {
                    loadError
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(profile?.displayName ?? displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userID) { await load() }
        .refreshable { await load() }
        .alert("Не удалось выполнить действие", isPresented: Binding(
            get: { profile != nil && errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Попробуйте снова.")
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            if let profile {
                PublicProfilePhotoViewer(
                    photos: $photos,
                    initialPhotoID: photo.id,
                    profile: profile,
                    likeAction: toggleLike
                )
                .presentationBackground(.clear)
            }
        }
    }

    private func profileHeader(_ profile: PublicUserProfile) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            ProfileAvatar(initials: profile.initials, size: 96, imageData: avatarData)
            VStack(alignment: .leading, spacing: 7) {
                Text(profile.displayName)
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("@\(profile.username)")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.accentPrimary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Username: \(profile.username)")
                HStack(spacing: AppSpacing.sm) {
                    Label(String(format: "%.1f", profile.rating), systemImage: "star.fill")
                    if let distance = profile.distanceKm {
                        Label("\(distance.formatted()) км", systemImage: "location.fill")
                    }
                }
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func aboutCard(_ profile: PublicUserProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Label("О человеке", systemImage: "person.text.rectangle")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                let facts = profileFacts(profile)
                if facts.isEmpty && profile.bio?.nonEmpty == nil && profile.interests.isEmpty && profile.languages.isEmpty {
                    Label("Информация пока не заполнена", systemImage: "info.circle")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if !facts.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145), spacing: AppSpacing.sm)],
                        alignment: .leading,
                        spacing: AppSpacing.sm
                    ) {
                        ForEach(facts) { fact in
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: fact.symbol)
                                    .foregroundStyle(AppColors.accentPrimary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.title)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text(fact.value)
                                        .font(AppTypography.bodyMedium)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let bio = profile.bio?.nonEmpty {
                    profileSection(title: "О себе", symbol: "text.quote", text: bio)
                }
                if !profile.interests.isEmpty {
                    tagSection(title: "Интересы", symbol: "tag", values: profile.interests, tint: AppColors.accentPrimary)
                }
                if !profile.languages.isEmpty {
                    tagSection(title: "Языки", symbol: "globe", values: profile.languages, tint: AppColors.accentSecondary)
                }
            }
        }
    }

    private func photoGallery(_ profile: PublicUserProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Фотографии")
                            .font(AppTypography.sectionTitle)
                        Text(photos.isEmpty ? "Пока нет фотографий" : "\(photos.count) \(photoCountWord(photos.count))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(AppColors.accentPrimary)
                }

                if photos.isEmpty {
                    AppEmptyState(
                        symbol: "photo.on.rectangle.angled",
                        title: "Фотографий пока нет",
                        message: "Когда \(profile.displayName) добавит фотографии, они появятся здесь."
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: AppSpacing.sm)],
                        alignment: .leading,
                        spacing: AppSpacing.sm
                    ) {
                        ForEach(photos) { photo in
                            Button { selectedPhoto = photo } label: {
                                PublicProfilePhotoThumbnail(photo: photo)
                            }
                            .buttonStyle(AppPressButtonStyle())
                            .accessibilityLabel("Открыть фотографию \(profile.displayName)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func posts(_ profile: PublicUserProfile) -> some View {
        Label("Посты", systemImage: "square.grid.2x2.fill")
            .font(AppTypography.sectionTitle)
            .foregroundStyle(AppColors.textPrimary)

        if photos.isEmpty {
            GlassCard {
                AppEmptyState(
                    symbol: "rectangle.stack",
                    title: "Пока нет постов",
                    message: "Фотографии с описаниями пользователя появятся здесь."
                )
            }
        } else {
            LazyVStack(spacing: AppSpacing.md) {
                ForEach(photos) { photo in
                    PublicProfilePostCard(
                        profile: profile,
                        photo: photo,
                        avatarData: avatarData,
                        isLiking: likingPhotoIDs.contains(photo.id),
                        open: { selectedPhoto = photo },
                        like: { Task { await toggleLike(photo) } }
                    )
                }
            }
        }
    }

    private var loadError: some View {
        GlassCard {
            AppEmptyState(
                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                title: "Не удалось открыть профиль",
                message: errorMessage ?? "Проверьте подключение и попробуйте снова.",
                actionTitle: "Повторить"
            ) {
                Task { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let profileTask = appState.socialRepository.profile(userID: userID)
            async let mediaTask = appState.socialRepository.profilePhotos(userID: userID)
            let (loadedProfile, media) = try await (profileTask, mediaTask)
            profile = loadedProfile
            photos = media.photos
            if let avatar = media.avatar {
                avatarData = (try? await appState.socialRepository.content(path: avatar.contentPath)) ?? Data()
            } else if let avatarPath {
                avatarData = (try? await appState.socialRepository.content(path: avatarPath)) ?? Data()
            } else {
                avatarData = Data()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike(_ photo: ProfilePhoto) async {
        guard !likingPhotoIDs.contains(photo.id) else { return }
        likingPhotoIDs.insert(photo.id)
        defer { likingPhotoIDs.remove(photo.id) }
        do {
            let engagement = try await appState.socialRepository.setPhotoLiked(
                !photo.isLiked,
                photoID: photo.id
            )
            guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
            photos[index] = photos[index].updating(
                likeCount: engagement.likeCount,
                isLiked: engagement.isLiked
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func profileFacts(_ profile: PublicUserProfile) -> [PublicProfileFact] {
        [
            profile.age.map { PublicProfileFact(symbol: "calendar", title: "Возраст", value: "\($0)") },
            profile.city?.nonEmpty.map { PublicProfileFact(symbol: "mappin.and.ellipse", title: "Город", value: $0) },
            profile.occupation?.nonEmpty.map { PublicProfileFact(symbol: "briefcase.fill", title: "Занятие", value: $0) },
            profile.availability?.nonEmpty.map { PublicProfileFact(symbol: "clock.fill", title: "Свободное время", value: $0) },
            profile.preferredGroupSizeText.map { PublicProfileFact(symbol: "person.3.fill", title: "Формат компании", value: $0) },
            profile.relationshipStatus?.nonEmpty.map { PublicProfileFact(symbol: "heart.circle", title: "Отношения", value: $0) },
        ].compactMap { $0 }
    }

    private func profileSection(title: String, symbol: String, text: String) -> some View {
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: AppSpacing.xs)], alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(tint.opacity(0.13), in: Capsule())
                }
            }
        }
    }

    private func photoCountWord(_ count: Int) -> String {
        count == 1 ? "фотография" : (2...4).contains(count) ? "фотографии" : "фотографий"
    }
}

private struct PublicProfileFact: Identifiable {
    let symbol: String
    let title: String
    let value: String
    var id: String { "\(title)-\(value)" }
}

private struct PublicProfilePhotoThumbnail: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    @State private var data = Data()

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                MediaDecodedImage(data: data, cacheKey: photo.contentPath, maxPixelSize: 420, contentMode: .fill) {
                    Rectangle().fill(AppColors.surfaceSecondary).overlay { ProgressView() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if photo.likeCount > 0 {
                    Label("\(photo.likeCount)", systemImage: "heart.fill")
                        .font(AppTypography.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.48), in: Capsule())
                        .padding(6)
                }
            }
            .task(id: photo.id) {
                data = (try? await appState.socialRepository.content(path: photo.contentPath)) ?? Data()
            }
    }
}

private struct PublicProfilePostCard: View {
    @EnvironmentObject private var appState: AppState
    let profile: PublicUserProfile
    let photo: ProfilePhoto
    let avatarData: Data
    let isLiking: Bool
    let open: () -> Void
    let like: () -> Void
    @State private var imageData = Data()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    ProfileAvatar(initials: profile.initials, size: 42, imageData: avatarData)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(AppTypography.bodyMedium)
                        Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                }

                Button(action: open) {
                    Color.clear
                        .aspectRatio(1.08, contentMode: .fit)
                        .overlay {
                            MediaDecodedImage(data: imageData, cacheKey: photo.contentPath, maxPixelSize: 1_200, contentMode: .fill) {
                                Rectangle().fill(AppColors.surfaceSecondary).overlay { ProgressView() }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть фотографию")

                if let description = photo.description?.nonEmpty {
                    Text(description)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: like) {
                    Label(
                        photo.likeCount == 0 ? "Нравится" : "\(photo.likeCount)",
                        systemImage: photo.isLiked ? "heart.fill" : "heart"
                    )
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(photo.isLiked ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(isLiking)
                .opacity(isLiking ? 0.62 : 1)
                .accessibilityLabel(photo.isLiked ? "Убрать отметку нравится" : "Нравится")
                .accessibilityValue("Отметок нравится: \(photo.likeCount)")
            }
        }
        .task(id: photo.id) {
            imageData = (try? await appState.socialRepository.content(path: photo.contentPath)) ?? Data()
        }
    }
}

private struct PublicProfilePhotoViewer: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Binding var photos: [ProfilePhoto]
    let profile: PublicUserProfile
    let likeAction: (ProfilePhoto) async -> Void
    @State private var selectedID: UUID
    @State private var likingPhotoID: UUID?

    init(
        photos: Binding<[ProfilePhoto]>,
        initialPhotoID: UUID,
        profile: PublicUserProfile,
        likeAction: @escaping (ProfilePhoto) async -> Void
    ) {
        _photos = photos
        _selectedID = State(initialValue: initialPhotoID)
        self.profile = profile
        self.likeAction = likeAction
    }

    private var selectedPhoto: ProfilePhoto? {
        photos.first(where: { $0.id == selectedID })
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.78))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(photos) { photo in
                    PublicViewerPhotoPage(photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .padding(.vertical, 76)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.42), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                    Spacer()
                    Text(profile.displayName)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, AppSpacing.lg)

                Spacer()

                if let photo = selectedPhoto {
                    HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                        if let description = photo.description?.nonEmpty {
                            Text(description)
                                .font(AppTypography.bodyMedium)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        } else {
                            Spacer(minLength: 0)
                        }
                        Button { toggleLike(photo) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: photo.isLiked ? "heart.fill" : "heart")
                                if photo.likeCount > 0 {
                                    Text("\(photo.likeCount)")
                                        .font(AppTypography.badge)
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(photo.isLiked ? AppColors.accentSecondary : .white)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, photo.likeCount > 0 ? AppSpacing.xs : 0)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .disabled(likingPhotoID != nil)
                        .opacity(likingPhotoID == photo.id ? 0.62 : 1)
                        .accessibilityLabel(photo.isLiked ? "Убрать отметку нравится" : "Нравится")
                        .accessibilityValue("Отметок нравится: \(photo.likeCount)")
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.lg)
                }
            }
            .padding(.top, AppSpacing.xs)
        }
        .statusBarHidden()
    }

    private func toggleLike(_ photo: ProfilePhoto) {
        guard likingPhotoID == nil else { return }
        likingPhotoID = photo.id
        Task {
            await likeAction(photo)
            likingPhotoID = nil
        }
    }
}

private struct PublicViewerPhotoPage: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    @State private var data = Data()

    var body: some View {
        MediaDecodedImage(data: data, cacheKey: photo.contentPath, maxPixelSize: 2_400, contentMode: .fit) {
            ProgressView().tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.id) {
            data = (try? await appState.socialRepository.content(path: photo.contentPath)) ?? Data()
        }
        .accessibilityLabel("Фотография профиля")
    }
}
