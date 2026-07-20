import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatar: View {
    let initials: String
    let size: CGFloat
    var imageData = Data()

    var body: some View {
        MediaDecodedImage(
            data: imageData,
            maxPixelSize: Int((size * 3).rounded(.up)),
            contentMode: .fill
        ) {
            ZStack {
                Circle().fill(AppGradients.brand)
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textOnAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(AppColors.glassBorder.opacity(0.76), lineWidth: 2) }
        .appShadow(.floating)
        .accessibilityLabel(L10n.format("profile.avatar.accessibility %@", initials))
    }
}

struct AvatarPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initials: String
    let size: CGFloat
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPreparingAvatar = false
    @State private var isHistoryPresented = false
    @State private var cropDraft: AvatarCropDraft?
    @State private var avatarError: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                if !appState.profilePhotos.avatars.isEmpty {
                    isHistoryPresented = true
                }
            } label: {
                ZStack {
                    if appState.profilePhotos.avatars.count > 1 {
                        Circle()
                            .fill(AppColors.accentSecondary.opacity(0.32))
                            .frame(width: size, height: size)
                            .offset(x: 8, y: 3)
                        Circle()
                            .fill(AppColors.locationAccent.opacity(0.28))
                            .frame(width: size, height: size)
                            .offset(x: 4, y: 1)
                    }
                    ProfileAvatar(initials: initials, size: size, imageData: appState.avatarImageData)
                    if appState.profilePhotos.avatars.count > 1 {
                        Text("\(appState.profilePhotos.avatars.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.textOnAccent)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(AppColors.accentSecondary, in: Capsule())
                            .offset(x: -3, y: -3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.profilePhotos.avatars.isEmpty ? "Аватар" : "Открыть историю аватаров")

            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                Image(systemName: isPreparingAvatar ? "arrow.triangle.2.circlepath" : "camera.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 40, height: 40)
                    .background(AppColors.accentPrimary, in: Circle())
                    .overlay { Circle().strokeBorder(AppColors.glassBorder.opacity(0.82), lineWidth: 2) }
                    .rotationEffect(.degrees(isPreparingAvatar && !reduceMotion ? 360 : 0))
                    .animation(
                        isPreparingAvatar && !reduceMotion
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : nil,
                        value: isPreparingAvatar
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingAvatar)
            .accessibilityLabel("Добавить новый аватар")
            .accessibilityHint("Предыдущий аватар останется в истории")
        }
        .frame(width: size + 10, height: size + 4)
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                isPreparingAvatar = true
                defer {
                    isPreparingAvatar = false
                    selectedPhoto = nil
                }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw MediaCompressionError.unreadableImage
                    }
                    cropDraft = AvatarCropDraft(image: try await AvatarCropProcessor.prepareImage(from: data))
                } catch {
                    avatarError = error.localizedDescription
                }
            }
        }
        .fullScreenCover(item: $cropDraft) { draft in
            AvatarCropperView(image: draft.image) { croppedData in
                try await appState.uploadAvatar(croppedData)
            }
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $isHistoryPresented) {
            if let first = appState.profilePhotos.avatar ?? appState.profilePhotos.avatars.first {
                ProfilePhotoViewer(photos: appState.profilePhotos.avatars, initialPhoto: first)
                    .presentationBackground(.clear)
            }
        }
        .alert("Не удалось открыть фотографию", isPresented: Binding(
            get: { avatarError != nil },
            set: { if !$0 { avatarError = nil } }
        )) {
            Button("Закрыть", role: .cancel) { avatarError = nil }
        } message: {
            Text(avatarError ?? "Попробуйте выбрать другую фотографию.")
        }
    }
}

struct ProfilePhotoGallery: View {
    static let maximumPhotoCount = 12
    private static let previewPhotoCount = 6
    @EnvironmentObject private var appState: AppState
    @Binding var isExpanded: Bool
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var selectedGalleryPhoto: ProfilePhoto?
    @State private var isUploading = false

    private var photos: [ProfilePhoto] { appState.profilePhotos.photos }
    private var displayedPhotos: [ProfilePhoto] {
        isExpanded ? photos : Array(photos.prefix(Self.previewPhotoCount))
    }

    var body: some View {
        Group {
            if isExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88, maximum: 100), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    photoButtons
                    addPhotoButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        photoButtons
                        addPhotoButton
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isExpanded ? nil : 116, alignment: .top)
        .onChange(of: pickedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                isUploading = true
                defer {
                    isUploading = false
                    pickedPhoto = nil
                }
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let compressed = try? await MediaCompressionService().optimizeImage(data) else { return }
                try? await appState.uploadProfilePhoto(compressed)
            }
        }
        .fullScreenCover(item: $selectedGalleryPhoto) { photo in
            ProfilePhotoViewer(photos: photos, initialPhoto: photo)
                .presentationBackground(.clear)
        }
        .task { await appState.reloadProfileMedia() }
    }

    @ViewBuilder
    private var photoButtons: some View {
        ForEach(displayedPhotos) { photo in
            Button { selectedGalleryPhoto = photo } label: {
                ProfileGalleryThumbnail(photo: photo)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Открыть фотографию")
        }
    }

    @ViewBuilder
    private var addPhotoButton: some View {
        if photos.count < Self.maximumPhotoCount {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Group {
                    if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(GoNowTheme.primary)
                    }
                }
                .frame(width: 88, height: 112)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
            .accessibilityLabel("Добавить фотографию")
        }
    }
}

struct ProfileGalleryThumbnail: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    @State private var imageData = Data()

    var body: some View {
        MediaDecodedImage(
            data: imageData,
            cacheKey: photo.contentPath,
            maxPixelSize: 360,
            contentMode: .fill
        ) {
            Color.secondary.opacity(0.16)
                .overlay { ProgressView().controlSize(.small) }
        }
        .frame(width: 88, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.74), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if photo.likeCount > 0 {
                Label("\(photo.likeCount)", systemImage: "heart.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .task(id: photo.id) { imageData = await appState.profilePhotoData(photo) }
    }
}

struct ProfilePhotoViewer: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let photos: [ProfilePhoto]
    @State private var selectedID: UUID
    @State private var imageData: [UUID: Data] = [:]
    @State private var isDeleteConfirmationPresented = false
    @State private var isDescriptionPresented = false
    @State private var isDeleting = false
    @State private var likingPhotoID: UUID?
    @State private var saveNotice: String?

    init(photos: [ProfilePhoto], initialPhoto: ProfilePhoto) {
        self.photos = photos
        _selectedID = State(initialValue: initialPhoto.id)
    }

    private var selectedPhoto: ProfilePhoto? {
        let latest = appState.profilePhotos.photos + appState.profilePhotos.avatars
        return latest.first(where: { $0.id == selectedID }) ?? photos.first(where: { $0.id == selectedID })
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.76))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(photos) { photo in
                    ViewerPhotoPage(photo: photo) { data in imageData[photo.id] = data }
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .padding(.vertical, 76)

            VStack {
                HStack {
                    viewerButton(icon: "xmark", label: "Закрыть") { dismiss() }
                    Spacer()
                    Menu {
                        Button {
                            saveSelectedPhoto()
                        } label: {
                            Label("Скачать фотографию", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            isDescriptionPresented = true
                        } label: {
                            Label("Редактировать описание", systemImage: "square.and.pencil")
                        }
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.42), lineWidth: 1) }
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel("Действия с фотографией")
                }
                .padding(.horizontal, 20)

                Spacer()

                if let photo = selectedPhoto {
                    HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                        if let description = photo.description, !description.isEmpty {
                            Text(description)
                                .font(AppTypography.bodyMedium)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                                }
                        } else {
                            Spacer(minLength: 0)
                        }
                        if !photo.isAvatar {
                            Button {
                                toggleLike(photo)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: photo.isLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 17, weight: .semibold))
                                        .contentTransition(.symbolEffect(.replace))
                                    if photo.likeCount > 0 {
                                        Text("\(photo.likeCount)")
                                            .font(.caption.weight(.bold))
                                            .monospacedDigit()
                                    }
                                }
                                .foregroundStyle(photo.isLiked ? AppColors.accentSecondary : .white)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, photo.likeCount > 0 ? 8 : 0)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay { Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .disabled(likingPhotoID == photo.id)
                            .opacity(likingPhotoID == photo.id ? 0.62 : 1)
                            .animation(.easeOut(duration: 0.18), value: photo.isLiked)
                            .accessibilityLabel(photo.isLiked ? "Убрать отметку нравится" : "Нравится")
                            .accessibilityValue("Отметок нравится: \(photo.likeCount)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
            }
            .padding(.top, 8)
        }
        .statusBarHidden()
        .alert("Удалить фотографию?", isPresented: $isDeleteConfirmationPresented) {
            Button("Удалить", role: .destructive) { deleteSelectedPhoto() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить.")
        }
        .alert("Фотография", isPresented: Binding(
            get: { saveNotice != nil },
            set: { if !$0 { saveNotice = nil } }
        )) {
            Button("Готово", role: .cancel) { saveNotice = nil }
        } message: {
            Text(saveNotice ?? "")
        }
        .sheet(isPresented: $isDescriptionPresented) {
            if let photo = selectedPhoto {
                PhotoDescriptionEditor(photo: photo)
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private func deleteSelectedPhoto() {
        guard let photo = selectedPhoto else { return }
        Task {
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await appState.deleteProfilePhoto(photo)
                let remaining = photos.filter { $0.id != photo.id }
                if let next = remaining.first {
                    selectedID = next.id
                } else {
                    dismiss()
                }
            } catch { }
        }
    }

    private func saveSelectedPhoto() {
        guard let data = imageData[selectedID], let image = UIImage(data: data) else {
            saveNotice = "Фотография ещё загружается. Попробуйте снова."
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in saveNotice = "Разрешите сохранение фотографий в настройках iPhone." }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            Task { @MainActor in saveNotice = "Фотография сохранена в медиатеку." }
        }
    }

    private func toggleLike(_ photo: ProfilePhoto) {
        guard likingPhotoID == nil else { return }
        likingPhotoID = photo.id
        Task {
            defer { likingPhotoID = nil }
            try? await appState.setProfilePhotoLiked(!photo.isLiked, for: photo)
        }
    }

    private func viewerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.42), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ViewerPhotoPage: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    let onLoad: (Data) -> Void
    @State private var data = Data()

    var body: some View {
        GeometryReader { proxy in
            MediaDecodedImage(
                data: data,
                cacheKey: photo.contentPath,
                maxPixelSize: 2_400,
                contentMode: .fit
            ) {
                ProgressView().tint(.white)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: photo.id) {
            data = await appState.profilePhotoData(photo)
            onLoad(data)
        }
        .accessibilityLabel(photo.isAvatar ? "Аватар" : "Фотография профиля")
    }
}

private struct PhotoDescriptionEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let photo: ProfilePhoto
    @State private var description: String
    @State private var isSaving = false

    init(photo: ProfilePhoto) {
        self.photo = photo
        _description = State(initialValue: photo.description ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Добавьте контекст: где вы, что происходит или почему этот момент важен.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                TextEditor(text: $description)
                    .font(AppTypography.body)
                    .frame(minHeight: 150)
                    .padding(AppSpacing.sm)
                    .glassSurface(.regular, cornerRadius: AppRadius.control)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(description.count)/500")
                            .font(AppTypography.caption)
                            .foregroundStyle(description.count > 500 ? AppColors.error : AppColors.textMuted)
                            .padding(10)
                    }
                Spacer()
            }
            .padding(AppLayout.horizontalInset)
            .navigationTitle("Описание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохранение…" : "Сохранить") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            try? await appState.updateProfilePhotoDescription(description, for: photo)
                            dismiss()
                        }
                    }
                    .disabled(isSaving || description.count > 500)
                }
            }
        }
    }
}
