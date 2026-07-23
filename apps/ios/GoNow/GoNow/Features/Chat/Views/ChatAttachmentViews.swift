import AVFoundation
import AVKit
import QuickLook
import SwiftUI
import UIKit

struct ChatAttachmentView: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case "image": ChatImageAttachment(message: message)
        case "video": ChatVideoAttachment(message: message)
        case "audio", "voice": ChatAudioAttachment(message: message)
        default: ChatFileAttachment(message: message)
        }
    }
}

private struct ChatImageAttachment: View {
    @EnvironmentObject private var appState: AppState
    let message: ChatMessage
    @State private var data = Data()
    @State private var isExpanded = false

    var body: some View {
        Button { isExpanded = true } label: {
            Color.clear
                .aspectRatio(1.15, contentMode: .fit)
                .overlay {
                    MediaDecodedImage(
                        data: data,
                        cacheKey: message.contentPath,
                        maxPixelSize: 1_200,
                        contentMode: .fill
                    ) {
                        Rectangle().fill(AppColors.surfaceSecondary).overlay { ProgressView() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(data.isEmpty)
        .accessibilityLabel("Открыть фотографию")
        .task(id: message.contentPath) { await load() }
        .fullScreenCover(isPresented: $isExpanded) {
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea()
                MediaDecodedImage(
                    data: data,
                    cacheKey: message.contentPath,
                    maxPixelSize: 2_400,
                    contentMode: .fit
                ) {
                    ProgressView().tint(.white)
                }
                .padding(12)
                Button { isExpanded = false } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
                .accessibilityLabel("Закрыть")
            }
        }
    }

    private func load() async {
        guard let path = message.contentPath else { return }
        data = (try? await appState.socialRepository.content(path: path)) ?? Data()
    }
}

private struct ChatVideoAttachment: View {
    @EnvironmentObject private var appState: AppState
    let message: ChatMessage
    @State private var localURL: URL?
    @State private var thumbnailData = Data()
    @State private var isExpanded = false
    @State private var isLoading = true

    var body: some View {
        Button { isExpanded = true } label: {
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    MediaDecodedImage(
                        data: thumbnailData,
                        cacheKey: "video-thumbnail-\(message.id.uuidString)",
                        maxPixelSize: 900,
                        contentMode: .fill
                    ) {
                        Rectangle()
                            .fill(AppColors.surfaceSecondary)
                            .overlay { ProgressView("Видео") }
                    }
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.52), in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.72), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(localURL == nil || isLoading)
        .accessibilityLabel("Открыть видео на весь экран")
        .fullScreenCover(isPresented: $isExpanded) {
            if let localURL {
                ChatVideoViewer(url: localURL)
            }
        }
        .task(id: message.contentPath) { await load() }
        .onDisappear {
            guard !isExpanded, let localURL else { return }
            try? FileManager.default.removeItem(at: localURL)
            self.localURL = nil
            thumbnailData = Data()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let path = message.contentPath,
              let data = try? await appState.socialRepository.content(path: path) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(message.id.uuidString)
            .appendingPathExtension(message.attachmentName?.split(separator: ".").last.map(String.init) ?? "mp4")
        do {
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            localURL = url
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)
            guard let result = try? await generator.image(at: .zero) else { return }
            thumbnailData = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.72) ?? Data()
        } catch { }
    }
}

private struct ChatVideoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.78))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .horizontal)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.46), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.48), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(20)
            .accessibilityLabel("Закрыть видео")
        }
        .onAppear {
            try? AppAudioSession.activatePlayback(mode: .moviePlayback)
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
            AppAudioSession.deactivate()
        }
    }
}

private struct ChatAudioAttachment: View {
    @EnvironmentObject private var appState: AppState
    let message: ChatMessage
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTick = 0
    @State private var playbackUpdates: Task<Void, Never>?
    @State private var localURL: URL?
    @State private var loadFailed = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button { toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 44, height: 44)
                    .background(AppGradients.brand, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(player == nil)
            .accessibilityLabel(isPlaying ? "Пауза" : "Воспроизвести")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(index < progressBars ? AppColors.accentPrimary : AppColors.textMuted.opacity(0.35))
                            .frame(width: 3, height: CGFloat(8 + (index * 7 % 16)))
                    }
                }
                HStack {
                    Text(loadFailed ? "Не удалось загрузить аудио" : message.kind == "voice" ? "Голосовое сообщение" : message.attachmentName ?? "Аудио")
                        .lineLimit(1)
                    Spacer()
                    Text(timeText)
                        .monospacedDigit()
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .task(id: message.contentPath) { await load() }
        .onDisappear {
            playbackUpdates?.cancel()
            playbackUpdates = nil
            player?.stop()
            isPlaying = false
            if let localURL { try? FileManager.default.removeItem(at: localURL) }
            localURL = nil
            AppAudioSession.deactivate()
        }
    }

    private var progressBars: Int {
        _ = playbackTick
        guard let player, player.duration > 0 else { return 0 }
        return Int((player.currentTime / player.duration * 18).rounded())
    }
    private var timeText: String {
        _ = playbackTick
        let seconds = player.map { isPlaying ? $0.currentTime : $0.duration } ?? message.durationSeconds ?? 0
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    private func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            playbackUpdates?.cancel()
            playbackUpdates = nil
            AppAudioSession.deactivate()
        } else {
            let mode: AVAudioSession.Mode = message.kind == "voice" ? .spokenAudio : .default
            do {
                try AppAudioSession.activatePlayback(mode: mode)
            } catch {
                isPlaying = false
                return
            }
            if player.currentTime >= player.duration { player.currentTime = 0 }
            isPlaying = player.play()
            if isPlaying { startPlaybackUpdates(for: player) }
        }
    }

    private func startPlaybackUpdates(for player: AVAudioPlayer) {
        playbackUpdates?.cancel()
        playbackUpdates = Task { @MainActor in
            while !Task.isCancelled, player.isPlaying {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                playbackTick &+= 1
            }
            guard !Task.isCancelled else { return }
            isPlaying = false
            AppAudioSession.deactivate()
        }
    }
    private func load() async {
        loadFailed = false
        guard let path = message.contentPath else {
            loadFailed = true
            return
        }
        do {
            let data = try await appState.socialRepository.content(path: path)
            let fileExtension = message.attachmentName?
                .split(separator: ".")
                .last
                .map(String.init) ?? (message.attachmentContentType == "audio/mp4" ? "m4a" : "audio")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat-audio-\(message.id.uuidString)")
                .appendingPathExtension(fileExtension)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
            localURL = url
            self.player = player
        } catch {
            player = nil
            loadFailed = true
        }
    }
}

private struct ChatFileAttachment: View {
    @EnvironmentObject private var appState: AppState
    let message: ChatMessage
    @State private var isLoading = false
    @State private var previewURL: URL?

    var body: some View {
        Button { open() } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.accentPrimary)
                    .frame(width: 46, height: 46)
                    .background(AppColors.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.attachmentName ?? "Файл")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                    Text(byteText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                if isLoading { ProgressView() } else { Image(systemName: "arrow.down.circle") }
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .quickLookPreview($previewURL)
    }

    private var byteText: String {
        ByteCountFormatter.string(fromByteCount: Int64(message.attachmentBytes ?? 0), countStyle: .file)
    }
    private func open() {
        guard let path = message.contentPath else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            guard let data = try? await appState.socialRepository.content(path: path) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(message.attachmentName ?? "attachment")
            do {
                try data.write(to: url, options: .atomic)
                previewURL = url
            } catch { }
        }
    }
}
