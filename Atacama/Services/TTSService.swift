//
//  TTSService.swift
//  Atacama
//
//  Text-to-speech read-back of the draft, so the author can proof by ear.
//  Wraps AVSpeechSynthesizer.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class TTSService: ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let delegateProxy = SpeechDelegateProxy()

    init() {
        delegateProxy.onFinish = { [weak self] in
            Task { @MainActor in self?.isSpeaking = false }
        }
        synthesizer.delegate = delegateProxy
    }

    /// Speak the given text. Stops any current utterance first.
    func speak(_ text: String) {
        let trimmed = text.readableAMLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configurePlaybackSessionIfNeeded()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop any current read-back.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Route speech through the normal playback channel on iOS so read-back is audible
    /// even when the hardware silent switch would otherwise suppress app audio.
    private func configurePlaybackSessionIfNeeded() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // If the audio session cannot be changed, still attempt speech synthesis;
            // AVSpeechSynthesizer can often speak with the existing session.
        }
        #endif
    }
}

/// Bridges AVSpeechSynthesizerDelegate (an NSObject protocol) to a closure.
private final class SpeechDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}

private extension String {
    /// Lightweight cleanup for read-back so inline AML footnote syntax is not spoken
    /// literally. Server preview remains authoritative for rendering.
    var readableAMLText: String {
        replacingOccurrences(
            of: #"\(<[A-Za-z]+>\s*([^)]*)\)"#,
            with: "$1",
            options: .regularExpression
        )
        .replacingOccurrences(of: "----", with: "")
    }
}
