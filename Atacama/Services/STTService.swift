//
//  STTService.swift
//  Atacama
//
//  Speech-to-text dictation using the Speech framework + AVAudioEngine, preferring
//  on-device recognition. Streams partial transcripts; the latest transcript for the
//  current utterance is published. The capture UI appends finalized utterances into
//  the draft body.
//
//  Note: microphone capture is unreliable in the iOS Simulator — test on a device.
//  Requires NSSpeechRecognitionUsageDescription and NSMicrophoneUsageDescription
//  in Info.plist.
//

import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class STTService: ObservableObject {
    /// Live transcript of the current utterance (partial, updates as you speak).
    @Published private(set) var transcript: String = ""
    /// Whether the engine is currently listening.
    @Published private(set) var isRecording = false
    /// Last error surfaced to the UI, if any.
    @Published var lastError: String?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Portion of the current recognition session that the UI has already committed
    /// into the editable draft while the recognizer may keep returning cumulative text.
    private var committedTranscriptPrefix = ""

    /// Request speech + mic authorization. Returns true if both are granted.
    func requestAuthorization() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuth else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start streaming dictation. `onUtterance` is called with the finalized text of
    /// each utterance so the caller can append it to the draft.
    func start(onUtterance: @escaping (String) -> Void) {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition is unavailable on this device."
            return
        }

        do {
            try configureAudioSession()
        } catch {
            lastError = "Could not start audio: \(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device recognition for privacy/offline when supported.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastError = "Could not start audio engine: \(error.localizedDescription)"
            cleanup()
            return
        }

        isRecording = true
        transcript = ""
        committedTranscriptPrefix = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = self.uncommittedTranscript(from: result.bestTranscription.formattedString)
                    if result.isFinal {
                        onUtterance(self.consumeTranscript())
                        self.transcript = ""
                        self.committedTranscriptPrefix = ""
                        // Restart for the next utterance while still "recording".
                        if self.isRecording {
                            self.restartRecognition(onUtterance: onUtterance)
                        }
                    }
                }
                if error != nil, self.isRecording {
                    // Recognition ended (often a pause/timeout); restart to keep going.
                    self.restartRecognition(onUtterance: onUtterance)
                }
            }
        }
    }

    /// Returns the current live transcript and clears it so callers can commit it
    /// before stopping, previewing, or submitting. Speech sometimes only delivers a
    /// partial result before the author taps Stop/Post; treating that partial as the
    /// final utterance keeps dictated text from being stranded outside the draft body.
    func consumeTranscript() -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if committedTranscriptPrefix.isEmpty {
            committedTranscriptPrefix = text
        } else {
            committedTranscriptPrefix += " " + text
        }
        transcript = ""
        return text
    }

    /// Stop dictation and release audio resources.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        request?.endAudio()
        task?.cancel()
        cleanup()
    }

    // MARK: - Private

    private func uncommittedTranscript(from recognizedText: String) -> String {
        let prefix = committedTranscriptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return recognizedText }
        guard recognizedText.hasPrefix(prefix) else { return recognizedText }

        let suffixStart = recognizedText.index(recognizedText.startIndex, offsetBy: prefix.count)
        return String(recognizedText[suffixStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restartRecognition(onUtterance: @escaping (String) -> Void) {
        task?.cancel()
        task = nil
        request = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        // Re-enter start() to spin up a fresh request/task.
        isRecording = false
        start(onUtterance: onUtterance)
    }

    private func cleanup() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request = nil
        task = nil
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }
}
