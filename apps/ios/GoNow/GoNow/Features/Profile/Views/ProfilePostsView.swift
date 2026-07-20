import SwiftUI
import UIKit

struct ProfilePostsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isGalleryExpanded: Bool
    @State private var selectedPhoto: ProfilePhoto?

    private var photos: [ProfilePhoto] { appState.profilePhotos.photos }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            GlassCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Фотографии")
                                .font(AppTypography.sectionTitle)
                            Text("Каждое фото — пост с описанием и лайками")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                                isGalleryExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isGalleryExpanded ? "chevron.up" : "chevron.down")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.accentPrimary)
                        .accessibilityLabel(isGalleryExpanded ? "Свернуть фотографии" : "Показать все фотографии")
                    }
                    ProfilePhotoGallery(isExpanded: $isGalleryExpanded)
                }
            }
            .frame(maxWidth: .infinity)

            if photos.isEmpty {
                GlassCard {
                    AppEmptyState(
                        symbol: "photo.on.rectangle.angled",
                        title: "Пока нет постов",
                        message: "Добавьте фотографию и описание — она появится здесь как первый пост."
                    )
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(photos) { photo in
                    ProfilePostCard(photo: photo) { selectedPhoto = photo }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .fullScreenCover(item: $selectedPhoto) { photo in
            ProfilePhotoViewer(photos: photos, initialPhoto: photo)
                .presentationBackground(.clear)
        }
    }
}

private struct ProfilePostCard: View {
    @EnvironmentObject private var appState: AppState
    let photo: ProfilePhoto
    let open: () -> Void
    @State private var imageData = Data()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    if let user = appState.currentUser {
                        ProfileAvatar(initials: user.initials, size: 42, imageData: appState.avatarImageData)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(AppTypography.bodyMedium)
                            Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .layoutPriority(1)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundStyle(AppColors.textSecondary)
                }

                Button(action: open) {
                    Color.clear
                    .aspectRatio(1.08, contentMode: .fit)
                    .overlay {
                        MediaDecodedImage(
                            data: imageData,
                            cacheKey: photo.contentPath,
                            maxPixelSize: 1_200,
                            contentMode: .fill
                        ) {
                            Rectangle()
                                .fill(AppColors.surfaceSecondary)
                                .overlay { ProgressView() }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(AppColors.glassBorder.opacity(0.55), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                if let description = photo.description, !description.isEmpty {
                    Text(description)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                }

                Button {
                    Task { try? await appState.setProfilePhotoLiked(!photo.isLiked, for: photo) }
                } label: {
                    Label(
                        photo.likeCount == 0 ? "Нравится" : "\(photo.likeCount)",
                        systemImage: photo.isLiked ? "heart.fill" : "heart"
                    )
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(photo.isLiked ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: photo.id) { imageData = await appState.profilePhotoData(photo) }
    }
}
