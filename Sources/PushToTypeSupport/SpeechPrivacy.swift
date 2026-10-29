import Foundation
import os

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

    /// What to do with an in-progress partial request when the chosen engine changes.
    /// The current request is dropped first. `.skip` means do not open another one.
    public static func reviseLivePartials(
        activeEngine: TranscriptionEngine?,
        newEngine: TranscriptionEngine,
        partialsEnabled: Bool,
        supportsOnDevice: Bool
    ) -> LivePartialRevision {
        guard partialsEnabled, let activeEngine, activeEngine != newEngine else {
            return .unchanged
        }
        return .replace(livePartials(engine: newEngine, supportsOnDevice: supportsOnDevice))
    }
}

public enum LivePartialRevision: Equatable, Sendable {
    case unchanged
    case replace(LivePartialPlan)
}

/// A speech request the live-partial path can configure without importing Speech.
public protocol LivePartialSpeechRequest: AnyObject {
    var requiresOnDeviceRecognition: Bool { get set }
    var shouldReportPartialResults: Bool { get set }
}

/// Turns a `LivePartialPlan` into a request. `.skip` does not call the factory.
public enum LivePartialRequests {
    public static func make<Request: LivePartialSpeechRequest>(
        plan: LivePartialPlan,
        makeRequest: () -> Request
    ) -> Request? {
        switch plan {
        case .skip:
            return nil
        case .recognize(let requiresOnDeviceRecognition):
            let request = makeRequest()
            request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
            request.shouldReportPartialResults = true
            return request
        }
    }
}

/// The feed flag and the speech request, read together by the audio tap.
///
/// The tap snapshots both under the lock and appends only to that pair.
/// A revoke that has already landed produces no append.
public final class LivePartialGate<Request: AnyObject>: @unchecked Sendable {
    private struct State {
        var feeds = false
        var request: Request?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func publish(feeds: Bool, request: Request?) {
        lock.withLock { state in
            state.feeds = feeds
            state.request = request
        }
    }

    /// Clear both fields. The returned request is the one that was live.
    @discardableResult
    public func revoke() -> Request? {
        lock.withLock { state in
            let previous = state.request
            state.feeds = false
            state.request = nil
            return previous
        }
    }

    /// Snapshot `(feeds, request)` under the lock and append only while that pair is still live.
    @discardableResult
    public func appendIfLive(_ use: (Request) -> Void) -> Bool {
        let snapshot = lock.withLock { state in
            (feeds: state.feeds, request: state.request)
        }
        guard snapshot.feeds, let request = snapshot.request else { return false }
        return lock.withLock { state in
            guard state.feeds, let current = state.request, current === request else { return false }
            use(current)
            return true
        }
    }
}
