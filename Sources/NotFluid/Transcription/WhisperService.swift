import Foundation

enum WhisperError: LocalizedError {
    case binaryMissing
    case modelMissing(String)
    case processFailed(String)
    case emptyOutput
    case translateUnsupported

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "whisper-cli not found. Run: brew install whisper-cpp"
        case .modelMissing(let name):
            return "Model missing: \(name). Run scripts/download-model.sh"
        case .processFailed(let msg):
            return msg
        case .emptyOutput:
            return "Whisper produced no text"
        case .translateUnsupported:
            return "This English-only model can't translate. Switch to Whisper Small (multilingual)."
        }
    }
}

/// Local Whisper via whisper.cpp — best small open-source dictation + translation stack.
///
/// Why Whisper Small?
/// - Open weights (MIT-style ecosystem via whisper.cpp)
/// - Native translate-to-English task
/// - Strong accuracy for its size (~466 MB full / quantized options)
/// - Metal-accelerated on Apple Silicon through whisper.cpp
actor WhisperService {
    private let modelsDir: URL
    private let supportDir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid", isDirectory: true)
        supportDir = base
        modelsDir = base.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }

    func ensureReady(model: WhisperModel) async -> ModelReadyStatus {
        let binary = resolveWhisperBinary()
        guard binary != nil else {
            return ModelReadyStatus(
                ready: false,
                message: "Install whisper.cpp: brew install whisper-cpp"
            )
        }

        let modelPath = modelsDir.appendingPathComponent(model.ggmlFileName)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return ModelReadyStatus(ready: true, message: "\(model.displayName) ready")
        }

        // Also check project-local Models/ folder (dev convenience)
        let projectModel = projectModelsDir()?.appendingPathComponent(model.ggmlFileName)
        if let projectModel, FileManager.default.fileExists(atPath: projectModel.path) {
            return ModelReadyStatus(ready: true, message: "\(model.displayName) ready (project)")
        }

        return ModelReadyStatus(
            ready: false,
            message: "Download \(model.ggmlFileName) — run scripts/download-model.sh \(model.rawValue)"
        )
    }

    func transcribe(
        audioURL: URL,
        model: WhisperModel,
        mode: DictationMode,
        language: String
    ) async throws -> String {
        if mode == .translate && !model.supportsTranslate {
            throw WhisperError.translateUnsupported
        }

        guard let binary = resolveWhisperBinary() else {
            throw WhisperError.binaryMissing
        }

        let modelPath = try resolveModelPath(model)

        // Capture already converts to 16 kHz mono — skip a second ffmpeg (saves ~50–150ms)
        let wavURL = try await ensureWhisperFriendlyWAV(audioURL)

        // Short push-to-talk clips: greedy decode + pinned language is much faster than full beam/auto
        let lang = (language == "auto" || language.isEmpty) ? "auto" : language
        let threads = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 1))

        var args: [String] = [
            "-m", modelPath.path,
            "-f", wavURL.path,
            "-nt",
            "-np",
            "-t", "\(threads)",
            "-l", lang,
            // Greedy (beam 1) — big win on short dictation; accuracy still solid for speech
            "-bs", "1",
            "-nth", "0.5",
            "-lpt", "-1.0",
            "-sns"
        ]

        if mode == .translate {
            args.append("-tr")
        }

        let outBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("notfluid-out-\(UUID().uuidString)")
        args += ["-of", outBase.path, "-otxt"]

        let result = try await runProcess(binary: binary, arguments: args)
        if wavURL != audioURL {
            try? FileManager.default.removeItem(at: wavURL)
        }

        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperError.processFailed(err.isEmpty ? "whisper-cli exited \(result.exitCode)" : err)
        }

        let txtURL = URL(fileURLWithPath: outBase.path + ".txt")
        var cleaned = ""
        if let data = try? Data(contentsOf: txtURL),
           let text = String(data: data, encoding: .utf8) {
            try? FileManager.default.removeItem(at: txtURL)
            cleaned = postProcess(text)
        }
        if cleaned.isEmpty {
            cleaned = postProcess(result.stdout)
        }
        if cleaned.isEmpty { throw WhisperError.emptyOutput }

        // Common silence hallucination — treat as empty so UI can say "no speech"
        let lower = cleaned.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        let hallucinations: Set<String> = [
            "you", "thank you", "thanks for watching", "thanks for listening",
            "subscribe", "the", "a", "i", "yeah", "yes", "okay", "ok", "hmm", "uh"
        ]
        if hallucinations.contains(lower) {
            // Keep short real answers like "yes" only if audio was long — caller already checks length
            // Still return it; AppState can show it. Prefer returning for "yes"/"ok" but not "you" alone.
            if lower == "you" || lower == "thank you" || lower == "thanks for watching" {
                throw WhisperError.emptyOutput
            }
        }
        return cleaned
    }

    /// Only re-encode if capture didn't already produce a 16 kHz mono WAV.
    private func ensureWhisperFriendlyWAV(_ url: URL) async throws -> URL {
        let name = url.lastPathComponent
        // AudioCaptureService names converted files `notfluid-16k-*.wav`
        if name.hasPrefix("notfluid-16k-"), name.hasSuffix(".wav") {
            return url
        }
        // Already a wav that might be fine — still convert CAF/other containers once
        if name.hasSuffix(".wav"), name.contains("16k") {
            return url
        }

        guard let ffmpeg = which("ffmpeg") ?? (
            FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
            ? "/opt/homebrew/bin/ffmpeg" : nil
        ) else {
            return url
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("notfluid-16k-\(UUID().uuidString).wav")
        let result = try await runProcess(
            binary: URL(fileURLWithPath: ffmpeg),
            arguments: [
                "-y", "-hide_banner", "-loglevel", "error",
                "-i", url.path,
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                out.path
            ]
        )
        if result.exitCode == 0, FileManager.default.fileExists(atPath: out.path) {
            return out
        }
        return url
    }

    // MARK: - Paths

    private func resolveWhisperBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            NSHomeDirectory() + "/.local/bin/whisper-cli"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // which whisper-cli
        if let found = which("whisper-cli") ?? which("whisper-cpp") {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    private func resolveModelPath(_ model: WhisperModel) throws -> URL {
        let primary = modelsDir.appendingPathComponent(model.ggmlFileName)
        if FileManager.default.fileExists(atPath: primary.path) { return primary }

        if let project = projectModelsDir()?.appendingPathComponent(model.ggmlFileName),
           FileManager.default.fileExists(atPath: project.path) {
            return project
        }

        throw WhisperError.modelMissing(model.ggmlFileName)
    }

    private func projectModelsDir() -> URL? {
        // Walk up from CWD for dev runs: .../n0tfluid/Models
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Models")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in ["Desktop/PushToType/Models", "Desktop/n0tfluid/Models"] {
            let candidate = home.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    private func postProcess(_ raw: String) -> String {
        raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                // Drop whisper progress / banner lines
                if line.hasPrefix("whisper_") { return false }
                if line.hasPrefix("system_info:") { return false }
                if line.hasPrefix("main:") { return false }
                if line.contains("processing") && line.contains("ms") { return false }
                return true
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(binary: URL, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let proc = Process()
                    proc.executableURL = binary
                    proc.arguments = arguments
                    let out = Pipe()
                    let err = Pipe()
                    proc.standardOutput = out
                    proc.standardError = err
                    try proc.run()
                    proc.waitUntilExit()
                    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
