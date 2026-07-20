import AVFoundation
import Combine
import Foundation

struct VoiceRecording: Sendable {
    let data: Data
    let duration: Double
    let fileName: String
}

@MainActor
final class VoiceMessageRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    func start() async throws {
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { throw VoiceRecordingError.permissionDenied }
        try AppAudioSession.activateRecording()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gonow-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else { throw VoiceRecordingError.couldNotStart }
        self.recorder = recorder
        recordingURL = url
        duration = 0
        level = 0
        isRecording = true
        let meterTimer = Timer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updateRecordingMetrics),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(meterTimer, forMode: .common)
        timer = meterTimer
    }

    func stop() throws -> VoiceRecording {
        guard let recorder, let url = recordingURL else { throw VoiceRecordingError.noRecording }
        let recordedDuration = recorder.currentTime
        recorder.stop()
        finishSession()
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        guard recordedDuration >= 0.5, !data.isEmpty else { throw VoiceRecordingError.tooShort }
        return VoiceRecording(data: data, duration: recordedDuration, fileName: "voice-\(UUID().uuidString).m4a")
    }

    func cancel() {
        recorder?.stop()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        finishSession()
    }

    @objc private func updateRecordingMetrics() {
        guard let recorder else { return }
        recorder.updateMeters()
        duration = recorder.currentTime
        level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 45) / 45))
    }

    private func finishSession() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        recordingURL = nil
        isRecording = false
        duration = 0
        level = 0
        AppAudioSession.deactivate()
    }
}

enum VoiceRecordingError: LocalizedError {
    case permissionDenied, couldNotStart, noRecording, tooShort

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Разрешите доступ к микрофону в настройках iPhone."
        case .couldNotStart: "Не удалось начать запись. Проверьте микрофон."
        case .noRecording: "Запись не найдена."
        case .tooShort: "Удерживайте запись хотя бы полсекунды."
        }
    }
}
