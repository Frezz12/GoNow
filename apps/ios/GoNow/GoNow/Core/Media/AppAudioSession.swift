import AVFoundation

enum AppAudioSession {
    static func activatePlayback(mode: AVAudioSession.Mode = .default) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: mode,
            options: [.allowAirPlay, .allowBluetoothA2DP]
        )
        try session.setActive(true)
    }

    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
