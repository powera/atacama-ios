//
//  TTSService.swift
//  Atacama
//
//  Text-to-speech read-back of the draft, so the author can proof by ear.
//  Wraps AVSpeechSynthesizer.
//

import AVFoundation
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
