import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatar: View {
    let initials: String
    let size: CGFloat
    var imageData = Data()

    var body: some View {
        ZStack {
            if let image = UIImage(data: imageData), !imageData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(GoNowTheme.buttonGradient, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(.white.opacity(0.76), lineWidth: 2) }
        .shadow(color: GoNowTheme.primary.opacity(0.28), radius: 12, y: 6)
        .accessibilityLabel("Аватар пользователя \(initials)")
    }
}

struct AvatarPicker: View {
    @EnvironmentObject private var appState: AppState
    let initials: String
    let size: CGFloat
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isHovering = false
    @State private var isUploading = false

    var body: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(initials: initials, size: size, imageData: appState.avatarImageData)
                Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(GoNowTheme.primary, in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.82), lineWidth: 2) }
                    .offset(x: 2, y: 2)
                    .rotationEffect(.degrees(isUploading ? 360 : 0))
                    .animation(isUploading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isUploading)
            }
            .overlay {
                if isHovering {
                    Circle()
                        .fill(.black.opacity(0.28))
                        .overlay { Image(systemName: "camera.fill").font(.title2).foregroundStyle(.white) }
                        .frame(width: size, height: size)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .onHover { isHovering = $0 }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.gonowProfileJPEG() else { return }
                isUploading = true
                defer {
                    isUploading = false
                    selectedPhoto = nil
                }
                try? await appState.uploadAvatar(compressed)
            }
        }
        .accessibilityLabel("Изменить фотографию профиля")
        .accessibilityHint("Открыть медиатеку и выбрать фотографию")
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
        .frame(height: isExpanded ? nil : 116, alignment: .top)
        .onChange(of: pickedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.gonowProfileJPEG() else { return }
                isUploading = true
                defer {
                    isUploading = false
                    pickedPhoto = nil
                }
                try? await appState.uploadProfilePhoto(compressed)
            }
        }
        .fullScreenCover(item: $selectedGalleryPhoto) { photo in
            ProfilePhotoViewer(photo: photo)
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
            .accessibilityLabel("Открыть личную фотографию")
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
            .accessibilityLabel("Добавить личную фотографию")
            .accessibilityHint("Открыть медиатеку")
        }
    }
}

struct ProfileGalleryThumbnail: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    @State private var imageData = Data()

    var body: some View {
        Group {
            if let image = UIImage(data: imageData), !imageData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.16)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(width: 88, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.74), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .task(id: photo.id) { imageData = await appState.profilePhotoData(photo) }
    }
}

struct ProfilePhotoViewer: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var imageData = Data()
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleting = false
    let photo: ProfilePhoto

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                Group {
                    if let image = UIImage(data: imageData), !imageData.isEmpty {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: proxy.size.width - 24, height: proxy.size.height - 148)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2 + 18)
                .accessibilityLabel("Личная фотография")
            }

            HStack {
                viewerButton(icon: "xmark", label: "Закрыть просмотр") { dismiss() }
                Spacer()
                viewerButton(icon: isDeleting ? "hourglass" : "trash", label: "Удалить фотографию") {
                    isDeleteConfirmationPresented = true
                }
                .foregroundStyle(.red)
                .disabled(isDeleting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .task { imageData = await appState.profilePhotoData(photo) }
        .alert("Удалить фотографию?", isPresented: $isDeleteConfirmationPresented) {
            Button("Удалить", role: .destructive) {
                Task {
                    isDeleting = true
                    defer { isDeleting = false }
                    do {
                        try await appState.deleteProfilePhoto(photo)
                        dismiss()
                    } catch { }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить.")
        }
    }

    private func viewerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.48), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension UIImage {
    func gonowProfileJPEG(maxDimension: CGFloat = 1_600, compressionQuality: CGFloat = 0.76) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else {
            return jpegData(compressionQuality: compressionQuality)
        }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
