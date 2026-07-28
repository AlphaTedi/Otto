import AVFoundation
import Foundation
import Speech

// MARK: - VoiceTranscriber — on-device speech to text (VC-2)
//
// Streams microphone audio through SFSpeechRecognizer with
// `requiresOnDeviceRecognition = true`, publishing a live transcript and a
// live input level for the waveform.
//
// PRIVACY IS A HARD CONSTRAINT, NOT A PREFERENCE: if on-device recognition
// isn't supported for the chosen locale, this refuses to start rather than
// letting Speech fall back to Apple's servers. "Nothing leaves your Mac" is
// a claim the UI makes out loud (PRD §2), so the code must make it
// unconditionally true.
//
// Engine note: the PRD names `SpeechAnalyzer` (macOS 26+). This type is the
// seam for that — swapping the transcription backend means reimplementing
// `start`/`stop` here and nothing else. SFSpeechRecognizer is used today
// because it is on-device capable on this hardware (verified:
// supportsOnDeviceRecognition == true) and works on every OS the app
// supports, including macOS 26.

@MainActor
final class VoiceTranscriber: ObservableObject {

    enum StartFailure: Error, LocalizedError {
        case notAuthorized
        case onDeviceUnavailable
        case recognizerUnavailable
        case audioEngineFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:        return L10n.t("voice.err.permission")
            case .onDeviceUnavailable:  return L10n.t("voice.err.onDevice")
            case .recognizerUnavailable: return L10n.t("voice.err.recognizer")
            case .audioEngineFailed(let detail): return detail
            }
        }
    }

    /// Live, provisional text — replaced wholesale on every partial result.
    @Published private(set) var transcript = ""
    /// Normalized 0…1 input level driving the waveform bars.
    @Published private(set) var level: CGFloat = 0

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Recognition locale follows the app's language setting, falling back to
    /// en-US when the user's language has no on-device model.
    private static func preferredLocale() -> Locale {
        let appLocale = Locale(identifier: L10n.languageCode)
        let supported = SFSpeechRecognizer.supportedLocales()
        if supported.contains(where: { $0.identifier.hasPrefix(L10n.languageCode) }) {
            return appLocale
        }
        return Locale(identifier: "en-US")
    }

    /// True when this Mac can transcribe entirely on-device — the only mode
    /// this app will use.
    static var isOnDeviceAvailable: Bool {
        guard let rec = SFSpeechRecognizer(locale: preferredLocale()) else { return false }
        return rec.supportsOnDeviceRecognition
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return .authorized }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// Microphone access is a SEPARATE grant from speech recognition. Without
    /// it the input node reports an unusable format and CoreAudio fails with
    /// -10877 — so this must be requested before touching the engine.
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }

    // MARK: Lifecycle

    func start() async throws {
        stop()   // idempotent: never stack two sessions

        guard await Self.requestMicrophoneAccess() else {
            throw StartFailure.notAuthorized
        }
        guard await Self.requestAuthorization() == .authorized else {
            throw StartFailure.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Self.preferredLocale()),
              recognizer.isAvailable else {
            throw StartFailure.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // Refuse rather than transcribe in the cloud.
            throw StartFailure.onDeviceUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true      // the whole point
        self.request = request

        transcript = ""
        level = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A zero sample rate OR zero channels means there's no usable input
        // device — installing a tap with that format is what produces the
        // CoreAudio -10877 failure.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw StartFailure.audioEngineFailed(L10n.t("voice.err.noInput"))
        }

        input.removeTap(onBus: 0)
        // NOTE: this closure runs on a real-time audio thread — everything it
        // touches must be nonisolated and allocation-light. Main-actor work
        // is hopped explicitly via Task.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let peak = Self.normalizedLevel(of: buffer)
            Task { @MainActor [weak self] in self?.updateLevel(peak) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw StartFailure.audioEngineFailed(error.localizedDescription)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in self?.transcript = text }
        }
    }

    /// Ends capture and returns the final transcript.
    @discardableResult
    func stop() -> String {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        recognizer = nil
        level = 0
        return transcript
    }

    // MARK: Level metering

    private func updateLevel(_ peak: CGFloat) {
        // Light smoothing so bars glide instead of strobing frame to frame.
        level = level * 0.6 + peak * 0.4
    }

    /// `nonisolated` is load-bearing: the audio tap calls this from a
    /// real-time CoreAudio thread. Without it the method inherits this
    /// class's @MainActor isolation and libdispatch traps with
    /// "BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on
    /// queue [main]" — an instant crash the moment the mic starts.
    nonisolated private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        // Speech RMS sits well below 1.0 — scale into a usable 0…1 range.
        return CGFloat(min(1, max(0, rms * 12)))
    }
}
