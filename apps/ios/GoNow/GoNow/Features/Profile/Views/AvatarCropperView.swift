import Foundation
import ImageIO
import SwiftUI
import UIKit

struct AvatarCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum AvatarCropProcessor {
    private static let preparationMaxPixelSize = 4_096
    private static let outputPixelSize: CGFloat = 1_024

    static func prepareImage(from data: Data) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw MediaCompressionError.unreadableImage
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: preparationMaxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw MediaCompressionError.unreadableImage
            }
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }.value
    }

    static func croppedJPEG(
        from image: UIImage,
        cropSide: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let sourceImage = image.cgImage else { throw MediaCompressionError.unreadableImage }
            let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
            let sourceRect = AvatarCropGeometry.sourceRect(
                imageSize: imageSize,
                cropSide: cropSide,
                zoom: zoom,
                offset: offset
            )
            let pixelRect = CGRect(
                x: max(0, floor(sourceRect.minX)),
                y: max(0, floor(sourceRect.minY)),
                width: min(CGFloat(sourceImage.width), ceil(sourceRect.maxX)) - max(0, floor(sourceRect.minX)),
                height: min(CGFloat(sourceImage.height), ceil(sourceRect.maxY)) - max(0, floor(sourceRect.minY))
            )
            guard pixelRect.width > 0,
                  pixelRect.height > 0,
                  let cropped = sourceImage.cropping(to: pixelRect) else {
                throw MediaCompressionError.unreadableImage
            }

            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = 1
            format.opaque = true
            let outputSize = CGSize(width: outputPixelSize, height: outputPixelSize)
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
            let data = renderer.jpegData(withCompressionQuality: 0.78) { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: outputSize))
                UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outputSize))
            }
            guard !data.isEmpty else { throw MediaCompressionError.unreadableImage }
            return data
        }.value
    }
}

struct AvatarCropGeometry {
    static func minimumScale(imageSize: CGSize, cropSide: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, cropSide > 0 else { return 1 }
        return max(cropSide / imageSize.width, cropSide / imageSize.height)
    }

    static func clampedOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        cropSide: CGFloat,
        zoom: CGFloat
    ) -> CGSize {
        let renderedScale = minimumScale(imageSize: imageSize, cropSide: cropSide) * max(1, zoom)
        let maximumX = max(0, (imageSize.width * renderedScale - cropSide) / 2)
        let maximumY = max(0, (imageSize.height * renderedScale - cropSide) / 2)
        return CGSize(
            width: min(max(offset.width, -maximumX), maximumX),
            height: min(max(offset.height, -maximumY), maximumY)
        )
    }

    static func sourceRect(
        imageSize: CGSize,
        cropSide: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGRect {
        let renderedScale = minimumScale(imageSize: imageSize, cropSide: cropSide) * max(1, zoom)
        let safeOffset = clampedOffset(
            offset,
            imageSize: imageSize,
            cropSide: cropSide,
            zoom: zoom
        )
        let renderedSize = CGSize(
            width: imageSize.width * renderedScale,
            height: imageSize.height * renderedScale
        )
        let renderedOrigin = CGPoint(
            x: (cropSide - renderedSize.width) / 2 + safeOffset.width,
            y: (cropSide - renderedSize.height) / 2 + safeOffset.height
        )
        let side = cropSide / renderedScale
        let rect = CGRect(
            x: -renderedOrigin.x / renderedScale,
            y: -renderedOrigin.y / renderedScale,
            width: side,
            height: side
        )
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }
}

struct AvatarCropperView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (Data) async throws -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var pinchScale: CGFloat = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maximumZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSide = min(proxy.size.width - 32, proxy.size.height * 0.58, 430)
                VStack(spacing: AppSpacing.lg) {
                    Spacer(minLength: AppSpacing.sm)
                    cropCanvas(side: cropSide)
                    Text("Перемещайте фотографию пальцем и изменяйте масштаб, чтобы выбрать область аватара.")
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                    zoomControls(cropSide: cropSide)
                    Spacer(minLength: AppSpacing.sm)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .safeAreaInset(edge: .bottom) {
                    confirmButton(cropSide: cropSide)
                }
            }
            .background {
                Rectangle()
                    .fill(.black.opacity(0.88))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
            .navigationTitle("Новый аватар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("Не удалось сохранить аватар", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Попробуйте ещё раз.")
        }
    }

    private func cropCanvas(side: CGFloat) -> some View {
        let imageSize = image.size
        let effectiveZoom = min(max(zoom * pinchScale, 1), maximumZoom)
        let effectiveOffset = AvatarCropGeometry.clampedOffset(
            CGSize(
                width: offset.width + dragTranslation.width,
                height: offset.height + dragTranslation.height
            ),
            imageSize: imageSize,
            cropSide: side,
            zoom: effectiveZoom
        )
        let renderedScale = AvatarCropGeometry.minimumScale(imageSize: imageSize, cropSide: side) * effectiveZoom

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(
                    width: imageSize.width * renderedScale,
                    height: imageSize.height * renderedScale
                )
                .offset(effectiveOffset)

            AvatarCropOverlay()
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .gesture(dragGesture(imageSize: imageSize, cropSide: side, zoom: effectiveZoom))
        .simultaneousGesture(magnificationGesture(imageSize: imageSize, cropSide: side))
        .accessibilityLabel("Область кадрирования аватара")
        .accessibilityHint("Перемещайте изображение. Масштаб также можно изменить ползунком ниже.")
    }

    private func zoomControls(cropSide: CGFloat) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "photo")
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { zoom },
                    set: { updateZoom($0, cropSide: cropSide) }
                ),
                in: 1...maximumZoom
            )
            .tint(AppColors.accentPrimary)
            .accessibilityLabel("Масштаб фотографии")
            Image(systemName: "photo.fill")
                .font(.title3)
                .accessibilityHidden(true)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    zoom = 1
                    offset = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сбросить кадрирование")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.lg)
    }

    private func confirmButton(cropSide: CGFloat) -> some View {
        Button {
            confirm(cropSide: cropSide)
        } label: {
            Group {
                if isSaving {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView().tint(AppColors.textOnAccent)
                        Text("Сохраняем…")
                    }
                } else {
                    Label("Выбрать", systemImage: "checkmark")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GradientPrimaryButtonStyle())
        .disabled(isSaving)
        .padding(.horizontal, AppLayout.horizontalInset)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(.ultraThinMaterial)
    }

    private func dragGesture(imageSize: CGSize, cropSide: CGFloat, zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = AvatarCropGeometry.clampedOffset(
                    CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    ),
                    imageSize: imageSize,
                    cropSide: cropSide,
                    zoom: zoom
                )
            }
    }

    private func magnificationGesture(imageSize: CGSize, cropSide: CGFloat) -> some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                let updatedZoom = min(max(zoom * value, 1), maximumZoom)
                zoom = updatedZoom
                offset = AvatarCropGeometry.clampedOffset(
                    offset,
                    imageSize: imageSize,
                    cropSide: cropSide,
                    zoom: updatedZoom
                )
            }
    }

    private func updateZoom(_ value: CGFloat, cropSide: CGFloat) {
        zoom = value
        offset = AvatarCropGeometry.clampedOffset(
            offset,
            imageSize: image.size,
            cropSide: cropSide,
            zoom: value
        )
    }

    private func confirm(cropSide: CGFloat) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let safeOffset = AvatarCropGeometry.clampedOffset(
                    offset,
                    imageSize: image.size,
                    cropSide: cropSide,
                    zoom: zoom
                )
                let data = try await AvatarCropProcessor.croppedJPEG(
                    from: image,
                    cropSide: cropSide,
                    zoom: zoom,
                    offset: safeOffset
                )
                try await onConfirm(data)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AvatarCropOverlay: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let cropCircle = bounds.insetBy(dx: 2, dy: 2)

            var scrim = Path()
            scrim.addRect(bounds)
            scrim.addEllipse(in: cropCircle)
            context.fill(scrim, with: .color(.black.opacity(0.58)), style: FillStyle(eoFill: true))
            context.stroke(Path(ellipseIn: cropCircle), with: .color(.white.opacity(0.9)), lineWidth: 2)

            var guides = Path()
            for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                guides.move(to: CGPoint(x: size.width * fraction, y: 0))
                guides.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                guides.move(to: CGPoint(x: 0, y: size.height * fraction))
                guides.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.clip(to: Path(ellipseIn: cropCircle))
            context.stroke(guides, with: .color(.white.opacity(0.2)), lineWidth: 1)
        }
    }
}
