import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ChatMediaKind: String {
    case image
    case video

    var title: String { self == .video ? "Видео" : "Фотография" }
    var symbol: String { self == .video ? "video.fill" : "photo.fill" }
}

struct ChatMediaDraft: Identifiable {
    let id = UUID()
    let kind: ChatMediaKind
    let imageData: Data?
    let videoURL: URL?
    let originalBytes: Int64

    var previewImage: UIImage? { imageData.flatMap(UIImage.init(data:)) }
}

struct ChatPickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoNowPickedMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return ChatPickedVideo(url: target)
        }
    }
}

struct ChatMediaComposer: View {
    @Environment(\.dismiss) private var dismiss
    let draft: ChatMediaDraft
    let send: (ChatMediaDraft, MediaOptimizationQuality) -> Void
    @State private var quality: MediaOptimizationQuality = .dataSaver
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        preview
                        settings
                        Button {
                            send(draft, quality)
                            dismiss()
                        } label: {
                            Label("Отправить", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .accessibilityHint("Медиа будет сжато перед загрузкой")
                    }
                    .padding(AppLayout.horizontalInset)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .navigationTitle(draft.kind == .video ? "Отправить видео" : "Отправить фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = draft.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 440)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .accessibilityLabel("Выбранная фотография")
        } else if let url = draft.videoURL {
            VideoPlayer(player: player)
                .aspectRatio(9.0 / 14.0, contentMode: .fit)
                .frame(maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .accessibilityLabel("Предпросмотр выбранного видео")
                .onAppear {
                    if player == nil { player = AVPlayer(url: url) }
                }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Настройки отправки", systemImage: "slider.horizontal.3")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Picker("Качество", selection: $quality) {
                ForEach(MediaOptimizationQuality.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label(draft.kind.title, systemImage: draft.kind.symbol)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: draft.originalBytes, countStyle: .file))
                    .monospacedDigit()
            }
            .font(AppTypography.captionStrong)
            .foregroundStyle(AppColors.textSecondary)

            Label(
                quality == .dataSaver
                    ? "Максимально экономит трафик и быстрее отправляется"
                    : "Чуть выше детализация, размер файла больше",
                systemImage: "arrow.down.right.and.arrow.up.left"
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
    }

}

enum ChatUploadPhase: Equatable {
    case preparing
    case uploading(Double)

    var title: String {
        switch self {
        case .preparing: "Сжимаем медиа…"
        case .uploading(let value): "Загрузка · \(Int(value * 100))%"
        }
    }

    var progress: Double? {
        if case .uploading(let value) = self { return value }
        return nil
    }
}

struct ChatUploadPresentation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let symbol: String
    let previewData: Data?
    var phase: ChatUploadPhase

    init(title: String, symbol: String, previewData: Data? = nil, phase: ChatUploadPhase) {
        id = UUID()
        self.title = title
        self.symbol = symbol
        self.previewData = previewData
        self.phase = phase
    }
}

struct ChatOutgoingUploadCard: View {
    let upload: ChatUploadPresentation

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            preview
            VStack(alignment: .leading, spacing: 6) {
                Text(upload.title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(upload.phase.title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
                if let progress = upload.phase.progress {
                    ProgressView(value: progress)
                        .tint(AppColors.accentPrimary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: 330, alignment: .leading)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(upload.title). \(upload.phase.title)")
    }

    @ViewBuilder
    private var preview: some View {
        if let data = upload.previewData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Image(systemName: upload.symbol)
                .font(.title2)
                .foregroundStyle(AppColors.accentPrimary)
                .frame(width: 54, height: 54)
                .background(AppColors.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
