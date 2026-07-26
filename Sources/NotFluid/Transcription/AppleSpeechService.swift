import Foundation
import Speech
import AVFoundation

enum AppleSpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case noResult
    case recognitionFailed(String)
    case translateUnsupported
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech Recognition permission denied — System Settings → Privacy → Speech Recognition"
        case .recognizerUnavailable:
            return "macOS Speech recognizer unavailable for this language"
        case .noResult:
            return "No speech detected"
        case .recognitionFailed(let m):
            return m
        case .translateUnsupported:
            return "macOS Speech can't translate. Switch engine to Whisper."
        case .timeout:
            return "macOS Speech timed out"
        }
    }
}

/// Built-in macOS Speech framework — zero model download.
actor AppleSpeechService {
    func ensureReady(language: String) async -> ModelReadyStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            let locale = locale(for: language)
            if let r = SFSpeechRecognizer(locale: locale), r.isAvailable {
                return ModelReadyStatus(ready: true, message: "macOS Speech ready (\(locale.identifier))")
            }
            if let r = SFSpeechRecognizer(), r.isAvailable {
                return ModelReadyStatus(ready: true, message: "macOS Speech ready (system locale)")
            }
            return ModelReadyStatus(ready: false, message: "macOS Speech unavailable")
        case .denied, .restricted:
            return ModelReadyStatus(ready: false, message: "Speech Recognition permission denied")
        case .notDetermined:
            let ok = await requestAuthorization()
            return ok
                ? ModelReadyStatus(ready: true, message: "macOS Speech ready")
                : ModelReadyStatus(ready: false, message: "Speech Recognition not granted")
        @unknown default:
            return ModelReadyStatus(ready: false, message: "Speech Recognition status unknown")
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL, language: String, mode: DictationMode) async throws -> String {
        if mode == .translate {
            throw AppleSpeechError.translateUnsupported
        }
        // rewrite + transcribe both use normal STT

        let auth = SFSpeechRecognizer.authorizationStatus()
        if auth == .notDetermined {
            let ok = await requestAuthorization()
            if !ok { throw AppleSpeechError.notAuthorized }
        } else if auth != .authorized {
            throw AppleSpeechError.notAuthorized
        }

        let locale = locale(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        // Try on-device first when available; fall back to default (may use Apple servers).
        do {
            return try await runRecognition(
                recognizer: recognizer,
                audioURL: audioURL,
                onDevice: recognizer.supportsOnDeviceRecognition
            )
        } catch {
            if recognizer.supportsOnDeviceRecognition {
                // Retry without forcing on-device
                return try await runRecognition(
                    recognizer: recognizer,
                    audioURL: audioURL,
                    onDevice: false
                )
            }
            throw error
        }
    }

    private func runRecognition(
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        onDevice: Bool
    ) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice

        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            var lastPartial = ""
            var task: SFSpeechRecognitionTask?

            let lock = NSLock()
            func finish(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                body()
            }

            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { lastPartial = text }
                    if result.isFinal {
                        finish {
                            task?.cancel()
                            if text.isEmpty && lastPartial.isEmpty {
                                cont.resume(throwing: AppleSpeechError.noResult)
                            } else {
                                cont.resume(returning: text.isEmpty ? lastPartial : text)
                            }
                        }
                        return
                    }
                }
                if let error {
                    finish {
                        task?.cancel()
                        // Prefer last partial over hard fail when we got something
                        if !lastPartial.isEmpty {
                            cont.resume(returning: lastPartial)
                        } else {
                            cont.resume(throwing: AppleSpeechError.recognitionFailed(error.localizedDescription))
                        }
                    }
                }
            }

            // Timeout — never hang forever
            Task {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                finish {
                    task?.cancel()
                    if !lastPartial.isEmpty {
                        cont.resume(returning: lastPartial)
                    } else {
                        cont.resume(throwing: AppleSpeechError.timeout)
                    }
                }
            }
        }
    }

    private func locale(for language: String) -> Locale {
        if language == "auto" || language.isEmpty {
            return Locale.current
        }
        return Locale(identifier: language)
    }
}
