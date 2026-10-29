import Foundation

/// Who asked for macOS Speech on this take.
public enum SpeechTakeRoute: Equatable, Sendable {
    /// The user selected macOS Speech. On-device is preferred, then the recognizer's usual path.
    case chosenEngine
    /// Whisper could not run. This audio must stay on the Mac.
    case whisperFallback
}

/// What the next `SFSpeechURLRecognitionRequest` is allowed to do.
public enum SpeechRequestPlan: Equatable, Sendable {
    /// Start recognition. `requiresOnDeviceRecognition` is passed through to the request.
    case recognize(requiresOnDeviceRecognition: Bool)
    /// Do not send the audio. Show this Whisper message.
    case whisperUnavailable(String)
    /// The user-chosen speech attempt already failed. Surface that error.
    case rethrowSpeechError
}

/// Whether live partials may open a speech request while the hotkey is held.
public enum LivePartialPlan: Equatable, Sendable {
    /// Do not attach a recognizer. The microphone stays in the local recording only.
    case skip
    /// Append mic buffers to a speech request.
    case recognize(requiresOnDeviceRecognition: Bool)
}

/// Decides whether a speech request may leave the Mac.
///
/// A Whisper fallback never sets `requiresOnDeviceRecognition` to false.
/// If on-device recognition is missing or the on-device attempt fails, the plan is the Whisper message.
public enum SpeechPrivacy {
    public static func firstRequest(
        route: SpeechTakeRoute,
        supportsOnDevice: Bool,
        whisperMessage: String
    ) -> SpeechRequestPlan {
        switch route {
        case .chosenEngine:
            return .recognize(requiresOnDeviceRecognition: supportsOnDevice)
        case .whisperFallback:
            guard supportsOnDevice else {
                return .whisperUnavailable(whisperMessage)
            }
            return .recognize(requiresOnDeviceRecognition: true)
        }
    }

    public static func afterFailure(
        route: SpeechTakeRoute,
        attemptedOnDevice: Bool,
        whisperMessage: String
    ) -> SpeechRequestPlan {
        switch route {
        case .chosenEngine:
            if attemptedOnDevice {
                return .recognize(requiresOnDeviceRecognition: false)
            }
            return .rethrowSpeechError
        case .whisperFallback:
            return .whisperUnavailable(whisperMessage)
        }
    }

    /// Live partials leave the Mac only when the user chose macOS Speech.
    /// Any other engine uses on-device recognition, or no partials if that is unavailable.
    public static func livePartials(engine: TranscriptionEngine, supportsOnDevice: Bool) -> LivePartialPlan {
        switch engine {
        case .appleSpeech:
            return .recognize(requiresOnDeviceRecognition: false)
        case .whisper, .parakeet, .phonon, .openAI, .bark30, .bark30Clean, .bark30Plus:
            guard supportsOnDevice else { return .skip }
            return .recognize(requiresOnDeviceRecognition: true)
        }
    }
}
