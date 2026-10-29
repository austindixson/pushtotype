import Foundation
import Speech
import AVFoundation
import PushToTypeSupport

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

    func transcribe(
        audioURL: URL,
        language: String,
        mode: DictationMode,
        route: SpeechTakeRoute = .chosenEngine,
        whisperMessage: String = ""
    ) async throws -> String {
        if mode == .translate {
            throw AppleSpeechError.translateUnsupported
        }
        // rewrite + transcribe both use normal STT
        try await ensureAuthorized(route: route, whisperMessage: whisperMessage)

        let locale = locale(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            try throwSpeechOrWhisper(route: route, whisperMessage: whisperMessage, speech: AppleSpeechError.recognizerUnavailable)
        }

        let plan = SpeechPrivacy.firstRequest(
            route: route,
            supportsOnDevice: recognizer.supportsOnDeviceRecognition,
            whisperMessage: whisperMessage
        )
        return try await runPlanned(
            plan,
            recognizer: recognizer,
            audioURL: audioURL,
            route: route,
            whisperMessage: whisperMessage
        )
    }

    private func ensureAuthorized(route: SpeechTakeRoute, whisperMessage: String) async throws {
        let auth = SFSpeechRecognizer.authorizationStatus()
        if auth == .notDetermined {
            let ok = await requestAuthorization()
            if ok { return }
            try throwSpeechOrWhisper(route: route, whisperMessage: whisperMessage, speech: AppleSpeechError.notAuthorized)
        } else if auth != .authorized {
            try throwSpeechOrWhisper(route: route, whisperMessage: whisperMessage, speech: AppleSpeechError.notAuthorized)
        }
    }

    /// A Whisper fallback never opens a second request with on-device recognition turned off.
    private func runPlanned(
        _ plan: SpeechRequestPlan,
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        route: SpeechTakeRoute,
        whisperMessage: String
    ) async throws -> String {
        switch plan {
        case .recognize(let requiresOnDevice):
            do {
                return try await runRecognition(
                    recognizer: recognizer,
                    audioURL: audioURL,
                    onDevice: requiresOnDevice,
                    route: route,
                    whisperMessage: whisperMessage
                )
            } catch {
                let next = SpeechPrivacy.afterFailure(
                    route: route,
                    attemptedOnDevice: requiresOnDevice,
                    whisperMessage: whisperMessage
                )
                return try await finishPlanned(
                    next,
                    recognizer: recognizer,
                    audioURL: audioURL,
                    speechError: error,
                    route: route,
                    whisperMessage: whisperMessage
                )
            }
        case .whisperUnavailable(let message):
            throw WhisperError.processFailed(message)
        case .rethrowSpeechError:
            throw AppleSpeechError.recognizerUnavailable
        }
    }

    private func finishPlanned(
        _ plan: SpeechRequestPlan,
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        speechError: Error,
        route: SpeechTakeRoute,
        whisperMessage: String
    ) async throws -> String {
        switch plan {
        case .recognize(let requiresOnDevice):
            return try await runRecognition(
                recognizer: recognizer,
                audioURL: audioURL,
                onDevice: requiresOnDevice,
                route: route,
                whisperMessage: whisperMessage
            )
        case .whisperUnavailable(let message):
            throw WhisperError.processFailed(message)
        case .rethrowSpeechError:
            throw speechError
        }
    }

    private func throwSpeechOrWhisper(
        route: SpeechTakeRoute,
        whisperMessage: String,
        speech: Error
    ) throws -> Never {
        switch route {
        case .whisperFallback:
            throw WhisperError.processFailed(whisperMessage)
        case .chosenEngine:
            throw speech
        }
    }

    private func runRecognition(
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        onDevice: Bool,
        route: SpeechTakeRoute,
        whisperMessage: String
    ) async throws -> String {
        if route == .whisperFallback && !onDevice {
            throw WhisperError.processFailed(whisperMessage)
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = DevLexicon.contextualStrings()

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
