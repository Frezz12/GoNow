import SwiftUI
import PhotosUI
import UIKit
import Foundation

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
            .overlay {
                Circle().strokeBorder(.white.opacity(0.76), lineWidth: 2)
            }
            .shadow(color: GoNowTheme.primary.opacity(0.28), radius: 12, y: 6)
            .accessibilityLabel("Аватар пользователя \(initials)")
    }
}

struct AvatarPicker: View {
    let initials: String
    let size: CGFloat
    @AppStorage("gonow.profile.avatar.version") private var avatarVersion = 0
    @State private var avatarImageData = Data()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isHovering = false

    var body: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(initials: initials, size: size, imageData: avatarImageData)
                Image(systemName: "camera.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(GoNowTheme.primary, in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.82), lineWidth: 2) }
                    .offset(x: 2, y: 2)
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
        .onHover { isHovering = $0 }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.gonowProfileJPEG() else { return }
                avatarImageData = compressed
                ProfileMediaStore.saveAvatar(compressed)
                avatarVersion += 1
            }
        }
        .onAppear {
            ProfileMediaStore.migrateLegacyMediaIfNeeded()
            avatarImageData = ProfileMediaStore.avatarData() ?? Data()
        }
        .accessibilityLabel("Изменить фотографию профиля")
        .accessibilityHint("Открыть медиатеку и выбрать фотографию")
    }
}

struct ProfilePhotoGallery: View {
    static let maximumPhotoCount = 12
    @State private var photos: [ProfileGalleryPhoto] = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var selectedGalleryPhoto: ProfileGalleryPhoto?
    @State private var isLimitPresented = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(photos) { photo in
                    Button {
                        selectedGalleryPhoto = photo
                    } label: {
                        ProfileGalleryThumbnail(photo: photo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Открыть личную фотографию")
                }

                if photos.count < Self.maximumPhotoCount {
                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(GoNowTheme.primary)
                            .frame(width: 88, height: 112)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить личную фотографию")
                    .accessibilityHint("Открыть медиатеку")
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 116)
        .onChange(of: pickedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.gonowProfileJPEG() else { return }
                addPhoto(compressed)
            }
        }
        .fullScreenCover(item: $selectedGalleryPhoto) { photo in
            ProfilePhotoViewer(photo: photo) {
                removePhoto(photo)
            }
        }
        .alert("Можно добавить до \(Self.maximumPhotoCount) фотографий", isPresented: $isLimitPresented) {
            Button("Готово", role: .cancel) {}
        }
        .onAppear { reloadPhotos() }
    }

    private func addPhoto(_ imageData: Data) {
        guard photos.count < Self.maximumPhotoCount else {
            isLimitPresented = true
            return
        }
        _ = ProfileMediaStore.addGalleryPhoto(imageData)
        reloadPhotos()
        pickedPhoto = nil
    }

    private func removePhoto(_ photo: ProfileGalleryPhoto) {
        ProfileMediaStore.removeGalleryPhoto(photo)
        reloadPhotos()
    }

    private func reloadPhotos() {
        ProfileMediaStore.migrateLegacyMediaIfNeeded()
        photos = ProfileMediaStore.galleryPhotos()
    }
}

struct ProfileGalleryThumbnail: View {
    let photo: ProfileGalleryPhoto

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: photo.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.16)
            }
        }
        .frame(width: 88, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.74), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }
}

struct ProfilePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false
    let photo: ProfileGalleryPhoto
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: photo.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Личная фотография")
            }
            VStack {
                HStack {
                    viewerButton(icon: "xmark", label: "Закрыть просмотр") { dismiss() }
                    Spacer()
                    viewerButton(icon: "trash", label: "Удалить фотографию") {
                        isDeleteConfirmationPresented = true
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .alert("Удалить фотографию?", isPresented: $isDeleteConfirmationPresented) {
            Button("Удалить", role: .destructive) {
                onDelete()
                dismiss()
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

struct ProfileGalleryPhoto: Identifiable, Hashable {
    let id: String
    let url: URL
}

enum ProfileMediaStore {
    private static let avatarFileName = "avatar.jpg"
    private static let galleryIDsKey = "gonow.profile.gallery.ids"
    private static let legacyAvatarKey = "gonow.profile.avatar"
    private static let legacyGalleryKey = "gonow.profile.gallery"

    private static var directoryURL: URL? {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = applicationSupport.appendingPathComponent("GoNowProfileMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func migrateLegacyMediaIfNeeded() {
        let defaults = UserDefaults.standard
        if let avatar = defaults.data(forKey: legacyAvatarKey) {
            if avatarData() == nil {
                saveAvatar(avatar)
            }
            defaults.removeObject(forKey: legacyAvatarKey)
        }
        if let galleryData = defaults.data(forKey: legacyGalleryKey),
           let legacyPhotos = try? JSONDecoder().decode([Data].self, from: galleryData) {
            for photo in legacyPhotos where galleryPhotos().count < ProfilePhotoGallery.maximumPhotoCount {
                _ = addGalleryPhoto(photo)
            }
            defaults.removeObject(forKey: legacyGalleryKey)
        }
    }

    static func avatarData() -> Data? {
        guard let directoryURL else { return nil }
        return try? Data(contentsOf: directoryURL.appendingPathComponent(avatarFileName))
    }

    static func saveAvatar(_ data: Data) {
        guard let directoryURL else { return }
        try? data.write(to: directoryURL.appendingPathComponent(avatarFileName), options: .atomic)
    }

    static func galleryPhotos() -> [ProfileGalleryPhoto] {
        guard let directoryURL else { return [] }
        return UserDefaults.standard.stringArray(forKey: galleryIDsKey)?.compactMap { id in
            let url = directoryURL.appendingPathComponent("\(id).jpg")
            return FileManager.default.fileExists(atPath: url.path) ? ProfileGalleryPhoto(id: id, url: url) : nil
        } ?? []
    }

    @discardableResult
    static func addGalleryPhoto(_ data: Data) -> ProfileGalleryPhoto? {
        guard let directoryURL else { return nil }
        let id = UUID().uuidString
        let url = directoryURL.appendingPathComponent("\(id).jpg")
        do {
            try data.write(to: url, options: .atomic)
            var ids = UserDefaults.standard.stringArray(forKey: galleryIDsKey) ?? []
            ids.append(id)
            UserDefaults.standard.set(ids, forKey: galleryIDsKey)
            return ProfileGalleryPhoto(id: id, url: url)
        } catch {
            return nil
        }
    }

    static func removeGalleryPhoto(_ photo: ProfileGalleryPhoto) {
        try? FileManager.default.removeItem(at: photo.url)
        var ids = UserDefaults.standard.stringArray(forKey: galleryIDsKey) ?? []
        ids.removeAll { $0 == photo.id }
        UserDefaults.standard.set(ids, forKey: galleryIDsKey)
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
