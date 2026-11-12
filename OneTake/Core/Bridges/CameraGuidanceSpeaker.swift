import Foundation
import AVFoundation

// MARK: - Camera guidance speaker

@Observable
final class CameraGuidanceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt = Date.distantPast
    private var lastMessage = ""

    /// Use the system's familiar default English voice. Selecting the highest downloaded voice
    /// quality often picked an unexpectedly emphatic premium voice.
    private var preferredVoice: AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice(language: "en-US") }

    func speak(_ message: String, minInterval: TimeInterval = 2.0, repeatInterval: TimeInterval = 4.5) {
        guard !message.isEmpty else { return }
        // Camera guidance changes as the actor moves. Let the current short prompt finish instead
        // of cutting it off and restarting with each new face-detection update.
        guard !synthesizer.isSpeaking else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpokenAt)
        if message == lastMessage {
            guard elapsed >= repeatInterval else { return }
        } else {
            guard elapsed >= minInterval else { return }
        }
        lastMessage = message
        lastSpokenAt = now
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.34
        utterance.voice = preferredVoice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastMessage = ""
    }
}
