import Foundation
import AVFoundation
import Speech

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case engineFailed(String)
    case permissionDenied
    case permissionPending
    case tooShort
    case silent

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone found"
        case .engineFailed(let m): return "Audio engine failed: \(m)"
        case .permissionDenied: return "Microphone permission denied — System Settings → Privacy → Microphone"
        case .permissionPending: return "Allow microphone access, then hold the hotkey again"
        case .tooShort: return "Recording too short — hold a bit longer while speaking"
        case .silent: return "Mic level too low — check input device / mute"
        }
    }
}

/// Crash-safe capture:
/// - Writes **native mic format** to a temp CAF/WAV (no live sample-rate conversion — that crashed ExtAudioFileWrite)
/// - Optional live Apple Speech partials from the same tap buffers
/// - On stop: `ffmpeg` → 16 kHz mono s16le WAV for Whisper (falls back to original file)
final class AudioCaptureService {
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var rawURL: URL?
    private var audioFile: AVAudioFile?
    private var isRunning = false
    private var startedAt: Date?
    private var peakLevel: Float = 0
    private var framesWritten: AVAudioFramePosition = 0

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    var isRecording: Bool { isRunning }

    func start(livePartials: Bool, language: String) throws {
        guard !isRunning else { return }
        try ensureMicrophonePermissionSyncSafe()
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioCaptureError.noInputDevice
        }

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine.reset()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notfluid-raw-\(UUID().uuidString).caf")
        rawURL = url
        peakLevel = 0
        framesWritten = 0

        let input = engine.inputNode
        // Use the node's native bus format — write the same format (no converter = no crash)
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioCaptureError.engineFailed("Invalid mic format. Is another app using the mic exclusively?")
        }

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: hwFormat.settings)
        } catch {
            throw AudioCaptureError.engineFailed("Could not open audio file: \(error.localizedDescription)")
        }

        let feedSpeech = livePartials && beginLiveSpeech(language: language)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }

            // Peak (float buffers)
            if let ch = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var peak: Float = 0
                for i in stride(from: 0, to: n, by: 4) { // light sampling
                    peak = max(peak, abs(ch[i]))
                }
                if peak > self.peakLevel { self.peakLevel = peak }
            }

            // Direct write — same format as tap (safe)
            do {
                try file.write(from: buffer)
                self.framesWritten += AVAudioFramePosition(buffer.frameLength)
            } catch {
                // Don't abort the realtime thread
            }

            if feedSpeech {
                self.recognitionRequest?.append(buffer)
            }
        }

        engine.prepare()
        try engine.start()
        startedAt = Date()
        isRunning = true
    }

    /// Stops capture and returns a Whisper-friendly 16 kHz mono WAV when possible.
    @discardableResult
    func stop() throws -> URL {
        guard isRunning else {
            if let rawURL, FileManager.default.fileExists(atPath: rawURL.path) {
                return try finalizeForSTT(rawURL)
            }
            throw AudioCaptureError.engineFailed("Not recording")
        }

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let peak = peakLevel
        let frames = framesWritten

        endLiveSpeech()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        // Finish file
        audioFile = nil
        isRunning = false
        startedAt = nil

        guard let rawURL else {
            throw AudioCaptureError.engineFailed("No output file")
        }

        // Allow snappier short utterances (was 0.25s / 2000 frames)
        if duration < 0.12 || frames < 800 {
            throw AudioCaptureError.tooShort
        }
        if peak < 0.004 {
            throw AudioCaptureError.silent
        }

        return try finalizeForSTT(rawURL)
    }

    func cancel() {
        endLiveSpeech()
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        audioFile = nil
        if let rawURL {
            try? FileManager.default.removeItem(at: rawURL)
        }
        rawURL = nil
        isRunning = false
        startedAt = nil
        peakLevel = 0
        framesWritten = 0
    }

    // MARK: - Convert for Whisper

    private func finalizeForSTT(_ raw: URL) throws -> URL {
        // Prefer ffmpeg → reliable s16le 16k mono
        if let ffmpeg = resolveFFmpeg() {
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("notfluid-16k-\(UUID().uuidString).wav")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ffmpeg)
            proc.arguments = [
                "-y", "-hide_banner", "-loglevel", "error", "-nostdin",
                "-threads", "1",
                "-i", raw.path,
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                out.path
            ]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               FileManager.default.fileExists(atPath: out.path) {
                try? FileManager.default.removeItem(at: raw)
                return out
            }
        }

        // Fallback: return raw CAF; Whisper/ffmpeg inside WhisperService may still handle it
        return raw
    }

    private func resolveFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    // MARK: - Live Speech

    private func beginLiveSpeech(language: String) -> Bool {
        let auth = SFSpeechRecognizer.authorizationStatus()
        if auth == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
            return false
        }
        guard auth == .authorized else { return false }

        let locale: Locale = (language == "auto" || language.isEmpty)
            ? .current
            : Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return false }
        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                self?.onPartial?(text)
            }
        }
        return true
    }

    private func endLiveSpeech() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
    }

    private func ensureMicrophonePermissionSyncSafe() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .denied, .restricted: throw AudioCaptureError.permissionDenied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw AudioCaptureError.permissionPending
        @unknown default: throw AudioCaptureError.permissionDenied
        }
    }
}
