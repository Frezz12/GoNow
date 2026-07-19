import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatConversationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let conversationID: UUID
    let title: String
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var proposalKind: ProposalKind?
    @State private var errorMessage: String?
    @State private var isMediaPickerPresented = false
    @State private var pickedMedia: PhotosPickerItem?
    @State private var mediaDraft: ChatMediaDraft?
    @State private var mediaDraftURLToCleanup: URL?
    @State private var isFileImporterPresented = false
    @State private var isPreparingAttachment = false
    @State private var isUploadingAttachment = false
    @State private var activeUpload: ChatUploadPresentation?
    @State private var typingUserID: UUID?
    @State private var lastTypingSentAt = Date.distantPast
    @StateObject private var voiceRecorder = VoiceMessageRecorder()

    var body: some View {
        ZStack {
            AuthBackdrop()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            if messages.isEmpty {
                                AppEmptyState(
                                    symbol: "sparkles",
                                    title: "Начните разговор",
                                    message: "Можно сразу предложить место или удобное время — собеседник проголосует в чате."
                                )
                                .padding(.top, 80)
                            }
                            ForEach(messages) { message in
                                ChatMessageRow(message: message) { vote(message) }
                                    .id(message.id)
                            }
                            if let activeUpload {
                                ChatOutgoingUploadCard(upload: activeUpload)
                                    .id("active-upload")
                            }
                        }
                        .frame(maxWidth: 680)
                        .padding(.horizontal, AppLayout.horizontalInset)
                        .padding(.vertical, AppSpacing.md)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        guard let last = messages.last else { return }
                        withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: activeUpload?.id) { _, value in
                        guard value != nil else { return }
                        withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                            proxy.scrollTo("active-upload", anchor: .bottom)
                        }
                    }
                }

                if typingUserID != nil {
                    Text("Собеседник печатает…")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppLayout.horizontalInset)
                        .padding(.vertical, 4)
                        .transition(.opacity)
                }

                composer
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .task { await listenRealtime() }
        .refreshable { await reload() }
        .photosPicker(
            isPresented: $isMediaPickerPresented,
            selection: $pickedMedia,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickedMedia) { _, item in
            guard let item else { return }
            Task { await preparePickedMedia(item) }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task { await uploadFile(url) }
        }
        .onChange(of: draft) { _, value in
            guard !value.isEmpty, Date.now.timeIntervalSince(lastTypingSentAt) > 1.5 else { return }
            lastTypingSentAt = .now
            Task { try? await appState.socialRepository.sendTyping(conversationID: conversationID) }
        }
        .onDisappear {
            voiceRecorder.cancel()
            if let url = mediaDraftURLToCleanup { try? FileManager.default.removeItem(at: url) }
            Task { await appState.socialRepository.closeLiveEvents(conversationID: conversationID) }
        }
        .sheet(item: $proposalKind) { kind in
            ProposalComposer(kind: kind) { body, detail in
                await send(kind: kind.apiKind, body: body, detail: detail)
            }
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $mediaDraft, onDismiss: {
            if let url = mediaDraftURLToCleanup { try? FileManager.default.removeItem(at: url) }
            mediaDraftURLToCleanup = nil
        }) { draft in
            ChatMediaComposer(draft: draft) { draft, quality in
                mediaDraftURLToCleanup = nil
                sendMediaDraft(draft, quality: quality)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .alert("Чат", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.sm) {
            if voiceRecorder.isRecording {
                Button { voiceRecorder.cancel() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppColors.error)
                        .frame(width: 44, height: 44)
                        .glassSurface(.subtle, cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отменить запись")

                VoiceRecordingIndicator(duration: voiceRecorder.duration, level: voiceRecorder.level)

                Button { finishVoiceRecording() } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(width: 46, height: 46)
                        .background(AppGradients.brand, in: Circle())
                }
                .buttonStyle(AppPressButtonStyle())
                .accessibilityLabel("Отправить голосовое сообщение")
            } else {
                Menu {
                    Button { isMediaPickerPresented = true } label: {
                        Label("Фото или видео", systemImage: "photo.on.rectangle")
                    }
                    Button { isFileImporterPresented = true } label: {
                        Label("Файл или аудио", systemImage: "doc.badge.plus")
                    }
                    Divider()
                    Button { proposalKind = .place } label: {
                        Label("Предложить место", systemImage: "mappin.and.ellipse")
                    }
                    Button { proposalKind = .time } label: {
                        Label("Предложить время", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    Group {
                        if isPreparingAttachment {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                                .font(.body.weight(.bold))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .glassSurface(.subtle, cornerRadius: 22)
                }
                .disabled(isUploadingAttachment || isPreparingAttachment)
                .accessibilityLabel("Добавить вложение или предложение")

                TextField("Сообщение", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(minHeight: 46)
                    .glassSurface(.regular, cornerRadius: 23)
                    .submitLabel(.send)
                    .onSubmit { sendText() }

                Button(action: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? startVoiceRecording : sendText) {
                    Image(systemName: actionSymbol)
                        .font(.body.weight(.bold))
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(width: 46, height: 46)
                        .background(AppGradients.brand, in: Circle())
                }
                .buttonStyle(AppPressButtonStyle())
                .disabled(isSending || isUploadingAttachment || isPreparingAttachment)
                .accessibilityLabel(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Записать голосовое сообщение" : "Отправить")
            }
        }
        .padding(.horizontal, AppLayout.horizontalInset)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private var actionSymbol: String {
        if isUploadingAttachment { return "arrow.triangle.2.circlepath" }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up"
    }

    private func reload() async {
        do { messages = try await appState.socialRepository.messages(conversationID: conversationID) }
        catch { errorMessage = error.localizedDescription }
    }

    private func listenRealtime() async {
        var retryDelay = Duration.seconds(1)
        while !Task.isCancelled {
            do {
                let events = try await appState.socialRepository.liveEvents(conversationID: conversationID)
                for try await event in events {
                    retryDelay = .seconds(1)
                    guard event.conversationId == conversationID else { continue }
                    switch event.event {
                    case "message", "messageUpdated":
                        await refreshMessage(event.messageId)
                    case "typing": showTyping(userID: event.userId)
                    default: break
                    }
                }
            } catch is CancellationError {
                break
            } catch { }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: retryDelay)
            retryDelay = min(retryDelay * 2, .seconds(30))
        }
    }

    private func refreshMessage(_ messageID: UUID?) async {
        guard let messageID else {
            await reload()
            return
        }
        do {
            appendIfNeeded(try await appState.socialRepository.message(
                conversationID: conversationID,
                messageID: messageID
            ))
        } catch is CancellationError {
            return
        } catch {
            // Compatibility fallback for servers that have not exposed the
            // single-message endpoint yet.
            await reload()
        }
    }

    private func showTyping(userID: UUID?) {
        guard userID != appState.currentUser?.id else { return }
        typingUserID = userID
        Task {
            try? await Task.sleep(for: .seconds(2))
            if typingUserID == userID { typingUserID = nil }
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await send(kind: "text", body: text, detail: nil) }
    }

    private func send(kind: String, body: String, detail: String?) async {
        isSending = true
        defer { isSending = false }
        do {
            let message = try await appState.socialRepository.sendMessage(
                conversationID: conversationID,
                kind: kind,
                body: body,
                detail: detail
            )
            appendIfNeeded(message)
        } catch { errorMessage = error.localizedDescription }
    }

    private func appendIfNeeded(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func startVoiceRecording() {
        Task {
            do { try await voiceRecorder.start() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func finishVoiceRecording() {
        do {
            let recording = try voiceRecorder.stop()
            Task {
                await uploadAttachment(
                    kind: "voice",
                    data: recording.data,
                    fileName: recording.fileName,
                    contentType: "audio/mp4",
                    duration: recording.duration
                )
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func preparePickedMedia(_ item: PhotosPickerItem) async {
        isPreparingAttachment = true
        defer {
            isPreparingAttachment = false
            pickedMedia = nil
        }
        guard let type = item.supportedContentTypes.first(where: {
            $0.conforms(to: .image) || $0.conforms(to: .movie)
        }) else {
            errorMessage = "Не удалось определить формат выбранного медиа."
            return
        }
        if type.conforms(to: .movie) {
            guard let video = try? await item.loadTransferable(type: ChatPickedVideo.self) else {
                errorMessage = "Не удалось прочитать выбранное видео."
                return
            }
            let bytes = (try? video.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            mediaDraft = ChatMediaDraft(
                kind: .video,
                imageData: nil,
                videoURL: video.url,
                originalBytes: bytes
            )
            mediaDraftURLToCleanup = video.url
        } else {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
                errorMessage = "Не удалось прочитать выбранную фотографию."
                return
            }
            mediaDraft = ChatMediaDraft(
                kind: .image,
                imageData: data,
                videoURL: nil,
                originalBytes: Int64(data.count)
            )
        }
    }

    private func sendMediaDraft(_ draft: ChatMediaDraft, quality: MediaOptimizationQuality) {
        mediaDraft = nil
        Task { await optimizeAndUpload(draft, quality: quality) }
    }

    private func optimizeAndUpload(_ draft: ChatMediaDraft, quality: MediaOptimizationQuality) async {
        let presentation = ChatUploadPresentation(
            title: draft.kind.title,
            symbol: draft.kind.symbol,
            previewData: draft.imageData,
            phase: .preparing
        )
        activeUpload = presentation
        isUploadingAttachment = true
        defer {
            if let url = draft.videoURL { try? FileManager.default.removeItem(at: url) }
        }
        do {
            let compressor = MediaCompressionService()
            switch draft.kind {
            case .image:
                guard let source = draft.imageData else { throw MediaCompressionError.unreadableImage }
                let data = try await compressor.optimizeImage(source, quality: quality)
                await performAttachmentUpload(
                    presentationID: presentation.id,
                    kind: "image",
                    data: data,
                    fileName: "photo-\(UUID().uuidString).jpg",
                    contentType: "image/jpeg"
                )
            case .video:
                guard let url = draft.videoURL else { throw MediaCompressionError.videoExportUnavailable }
                let video = try await compressor.optimizeVideo(at: url, quality: quality)
                await performAttachmentUpload(
                    presentationID: presentation.id,
                    kind: "video",
                    data: video.data,
                    fileName: video.fileName,
                    contentType: video.contentType,
                    duration: video.duration
                )
            }
        } catch is CancellationError {
            if activeUpload?.id == presentation.id { activeUpload = nil }
            isUploadingAttachment = false
        } catch {
            if activeUpload?.id == presentation.id { activeUpload = nil }
            isUploadingAttachment = false
            errorMessage = error.localizedDescription
        }
    }

    private func uploadFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        let kind = type.conforms(to: .audio) ? "audio" : "file"
        let presentation = ChatUploadPresentation(
            title: url.lastPathComponent,
            symbol: kind == "audio" ? "waveform" : "doc.fill",
            phase: .preparing
        )
        activeUpload = presentation
        isUploadingAttachment = true
        do {
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            await performAttachmentUpload(
                presentationID: presentation.id,
                kind: kind,
                data: data,
                fileName: url.lastPathComponent,
                contentType: type.preferredMIMEType ?? "application/octet-stream",
                duration: nil
            )
        } catch {
            if activeUpload?.id == presentation.id { activeUpload = nil }
            isUploadingAttachment = false
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAttachment(
        kind: String,
        data: Data,
        fileName: String,
        contentType: String,
        duration: Double? = nil,
        title: String? = nil,
        symbol: String? = nil
    ) async {
        let presentation = ChatUploadPresentation(
            title: title ?? attachmentTitle(kind: kind, fileName: fileName),
            symbol: symbol ?? attachmentSymbol(kind: kind),
            phase: .uploading(0)
        )
        activeUpload = presentation
        isUploadingAttachment = true
        await performAttachmentUpload(
            presentationID: presentation.id,
            kind: kind,
            data: data,
            fileName: fileName,
            contentType: contentType,
            duration: duration
        )
    }

    private func performAttachmentUpload(
        presentationID: UUID,
        kind: String,
        data: Data,
        fileName: String,
        contentType: String,
        duration: Double? = nil
    ) async {
        if activeUpload?.id == presentationID {
            activeUpload?.phase = .uploading(0)
        }
        defer {
            isUploadingAttachment = false
            if activeUpload?.id == presentationID { activeUpload = nil }
        }
        do {
            let message = try await appState.socialRepository.uploadAttachment(
                conversationID: conversationID,
                kind: kind,
                data: data,
                fileName: fileName,
                contentType: contentType,
                duration: duration,
                progress: { value in
                    Task { @MainActor in
                        guard activeUpload?.id == presentationID else { return }
                        activeUpload?.phase = .uploading(value)
                    }
                }
            )
            appendIfNeeded(message)
        } catch { errorMessage = error.localizedDescription }
    }

    private func attachmentTitle(kind: String, fileName: String) -> String {
        switch kind {
        case "voice": "Голосовое сообщение"
        case "audio": fileName
        case "video": "Видео"
        case "image": "Фотография"
        default: fileName
        }
    }

    private func attachmentSymbol(kind: String) -> String {
        switch kind {
        case "voice", "audio": "waveform"
        case "video": "video.fill"
        case "image": "photo.fill"
        default: "doc.fill"
        }
    }

    private func vote(_ message: ChatMessage) {
        guard !message.isVoted else { return }
        Task {
            do {
                let updated = try await appState.socialRepository.vote(
                    conversationID: conversationID,
                    messageID: message.id
                )
                if let index = messages.firstIndex(where: { $0.id == updated.id }) {
                    messages[index] = updated
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct VoiceRecordingIndicator: View {
    let duration: TimeInterval
    let level: Float

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(AppColors.error)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(AppColors.accentPrimary.opacity(Double(index) / 12 < Double(level) ? 1 : 0.25))
                        .frame(width: 3, height: CGFloat(8 + (index * 5 % 15)))
                }
            }
            Spacer(minLength: 4)
            Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                .font(AppTypography.captionStrong)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 46)
        .glassSurface(.regular, cornerRadius: 23)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Идёт запись голосового сообщения")
        .accessibilityValue(String(format: "%d минут %d секунд", Int(duration) / 60, Int(duration) % 60))
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let vote: () -> Void

    var body: some View {
        if message.kind == "system" {
            Text(message.body)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .glassSurface(.subtle, cornerRadius: AppRadius.control)
                .frame(maxWidth: .infinity)
        } else if message.isAttachment {
            attachmentCard
                .frame(maxWidth: 330, alignment: message.isMine ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        } else if message.isProposal {
            proposalCard
                .frame(maxWidth: 340, alignment: message.isMine ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        } else {
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                if !message.isMine {
                    Text(message.senderName)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentPrimary)
                }
                Text(message.body)
                    .font(AppTypography.body)
                    .foregroundStyle(message.isMine ? AppColors.textOnAccent : AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 11)
                    .background(
                        message.isMine ? AnyShapeStyle(AppGradients.brand) : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textMuted)
            }
            .frame(maxWidth: 310, alignment: message.isMine ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        }
    }

    private var attachmentCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !message.isMine {
                Text(message.senderName)
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.accentPrimary)
            }
            ChatAttachmentView(message: message)
            HStack {
                if showsAttachmentCaption {
                    Text(message.body)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(AppSpacing.sm)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
    }

    private var showsAttachmentCaption: Bool {
        message.kind == "image" || message.kind == "video"
    }

    private var proposalCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label(
                message.kind == "placeProposal" ? "Предложение места" : "Предложение времени",
                systemImage: message.kind == "placeProposal" ? "mappin.and.ellipse" : "calendar.badge.clock"
            )
            .font(AppTypography.captionStrong)
            .foregroundStyle(AppColors.accentPrimary)
            Text(message.body)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
            if let detail = message.proposalDetail, !detail.isEmpty {
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Divider().opacity(0.4)
            Button(action: vote) {
                Label(
                    message.isVoted ? "Вы выбрали · \(message.voteCount)" : "Подходит · \(message.voteCount)",
                    systemImage: message.isVoted ? "checkmark.circle.fill" : "hand.thumbsup"
                )
                .font(AppTypography.captionStrong)
                .foregroundStyle(message.isVoted ? AppColors.success : AppColors.accentPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(message.isVoted)
        }
        .padding(AppSpacing.md)
        .glassSurface(.prominent, cornerRadius: AppRadius.card)
    }
}

private enum ProposalKind: String, Identifiable {
    case place, time
    var id: String { rawValue }
    var apiKind: String { self == .place ? "placeProposal" : "timeProposal" }
}

private struct ProposalComposer: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ProposalKind
    let send: (String, String?) async -> Void
    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date.now.addingTimeInterval(3_600)
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if kind == .place {
                    AppTextField(title: "Место", text: $title, prompt: "Например, парк Царицыно")
                    AppTextField(title: "Детали", text: $detail, prompt: "Точка встречи или ссылка")
                } else {
                    DatePicker("Дата и время", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    AppTextField(title: "Комментарий", text: $detail, prompt: "Например, могу на час позже")
                }
                Spacer()
                Button {
                    submit()
                } label: {
                    Label(isSending ? "Отправляем…" : "Предложить", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .disabled(isSending || (kind == .place && title.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .padding(AppLayout.horizontalInset)
            .navigationTitle(kind == .place ? "Предложить место" : "Предложить время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        Task {
            isSending = true
            let body = kind == .place
                ? title.trimmingCharacters(in: .whitespacesAndNewlines)
                : date.formatted(date: .long, time: .shortened)
            await send(body, detail.nonEmpty)
            isSending = false
            dismiss()
        }
    }
}
