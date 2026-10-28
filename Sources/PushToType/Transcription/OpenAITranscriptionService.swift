import Foundation
import PushToTypeSupport

enum OpenAITranscriptionError: LocalizedError {
    case missingKey
    case emptyAudio
    case rejected(Int)
    case emptyOutput
    case translateUnsupported

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add an OpenAI API key in Settings. It is stored in the Keychain."
        case .emptyAudio:
            return "The recording was empty"
        case .rejected(let code):
            return "OpenAI rejected the transcription (HTTP \(code))"
        case .emptyOutput:
            return "OpenAI returned no text"
        case .translateUnsupported:
            return "OpenAI transcription does not translate. Switch to Whisper for translate."
        }
    }
}

/// `POST /v1/audio/transcriptions` with a user-supplied Platform API key.
actor OpenAITranscriptionService {
    func ensureReady() -> ModelReadyStatus {
        if APIKeyStore.hasKey {
            return ModelReadyStatus(ready: true, message: "OpenAI key is in the Keychain")
        }
        return ModelReadyStatus(ready: false, message: "Add an OpenAI API key in Settings")
    }

    func transcribe(audioURL: URL, mode: DictationMode) async throws -> String {
        if mode == .translate { throw OpenAITranscriptionError.translateUnsupported }
        guard let key = APIKeyStore.load() else { throw OpenAITranscriptionError.missingKey }
        if let text = try await post(fileURL: audioURL, apiKey: key, model: OpenAITranscriptionCatalog.primaryModel) {
            return text
        }
        if let text = try await post(fileURL: audioURL, apiKey: key, model: OpenAITranscriptionCatalog.fallbackModel) {
            return text
        }
        throw OpenAITranscriptionError.emptyOutput
    }

    private func post(fileURL: URL, apiKey: String, model: String) async throws -> String? {
        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            throw OpenAITranscriptionError.emptyAudio
        }
        var request = URLRequest(url: OpenAITranscriptionCatalog.endpoint)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(fileURL: fileURL, fileData: fileData, model: model, boundary: boundary)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if model == OpenAITranscriptionCatalog.fallbackModel {
                throw OpenAITranscriptionError.rejected(code)
            }
            return nil
        }
        return transcript(from: data)
    }

    private func body(fileURL: URL, fileData: Data, model: String, boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        let filename = fileURL.lastPathComponent.isEmpty ? "dictation.wav" : fileURL.lastPathComponent
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime(for: fileURL))\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append(field("model", model, boundary: boundary))
        append(field("response_format", "json", boundary: boundary))
        append("--\(boundary)--\r\n")
        return body
    }

    private func field(_ name: String, _ value: String, boundary: String) -> String {
        "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
    }

    private func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        default: return "audio/wav"
        }
    }

    private func transcript(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}
