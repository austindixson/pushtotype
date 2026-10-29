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
}
