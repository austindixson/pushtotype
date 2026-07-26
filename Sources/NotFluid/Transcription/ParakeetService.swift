import Foundation

enum ParakeetError: LocalizedError {
    case runtimeMissing
    case modelMissing(String)
    case workerFailed(String)
    case emptyOutput
    case translateUnsupported
    case timeout

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "Parakeet runtime not installed — open Settings → Speech → Install Parakeet"
        case .modelMissing(let m):
            return "Parakeet model missing: \(m). Run Install Parakeet in Settings."
        case .workerFailed(let m):
            return m
        case .emptyOutput:
            return "Parakeet produced no text"
        case .translateUnsupported:
            return "Parakeet doesn't do Whisper-style translate. Use Whisper for translate mode."
        case .timeout:
            return "Parakeet timed out"
        }
    }
}

enum ParakeetModel: String, CaseIterable, Identifiable {
    /// English TDT 0.6B v2 — best speed/accuracy for EN dictation
    case tdt06bV2 = "tdt-0.6b-v2"
    /// Multilingual TDT 0.6B v3 — 25 European languages
    case tdt06bV3 = "tdt-0.6b-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tdt06bV2: return "Parakeet TDT 0.6B v2 (English) ⭐"
        case .tdt06bV3: return "Parakeet TDT 0.6B v3 (Multilingual)"
        }
    }

    var detail: String {
        switch self {
        case .tdt06bV2:
            return "NVIDIA · ~600M · int8 ONNX · fastest local dictation · English"
        case .tdt06bV3:
            return "NVIDIA · ~600M · int8 ONNX · 25 European languages · auto-detect"
        }
    }

    /// Name passed to onnx-asr
    var onnxAsrName: String {
        switch self {
        case .tdt06bV2: return "nemo-parakeet-tdt-0.6b-v2"
        case .tdt06bV3: return "nemo-parakeet-tdt-0.6b-v3"
        }
    }

    /// Local cache folder under Application Support/NotFluid/Models/parakeet/
    var localDirName: String {
        switch self {
        case .tdt06bV2: return "tdt-0.6b-v2-int8"
        case .tdt06bV3: return "tdt-0.6b-v3-int8"
        }
    }
}

/// NVIDIA Parakeet via onnx-asr (persistent Python worker keeps model warm).
actor ParakeetService {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var loadedModel: ParakeetModel?
    private var ready = false
    private let lockQueue = DispatchQueue(label: "parakeet.worker.io")

    private var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid", isDirectory: true)
    }

    private var venvPython: URL {
        supportDir.appendingPathComponent("parakeet-venv/bin/python")
    }

    private var workerScript: URL {
        let inSupport = supportDir.appendingPathComponent("parakeet_worker.py")
        if FileManager.default.fileExists(atPath: inSupport.path) { return inSupport }
        // Dev / Resources next to bundle
        if let res = Bundle.main.resourceURL?.appendingPathComponent("parakeet_worker.py"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        // Project path
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/PushToType/Resources/parakeet_worker.py")
        return desktop
    }

    private func modelDir(_ model: ParakeetModel) -> URL {
        supportDir
            .appendingPathComponent("Models/parakeet", isDirectory: true)
            .appendingPathComponent(model.localDirName, isDirectory: true)
    }

    func isRuntimeInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && FileManager.default.fileExists(atPath: workerScript.path)
    }

    func isModelReady(_ model: ParakeetModel) -> Bool {
        let dir = modelDir(model)
        // Marker written by setup-parakeet.sh after HF download
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".ready").path) {
            return true
        }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return files.contains { $0.hasSuffix(".onnx") || $0.hasSuffix(".json") }
    }

    func ensureReady(model: ParakeetModel) async -> ModelReadyStatus {
        guard isRuntimeInstalled() else {
            return ModelReadyStatus(
                ready: false,
                message: "Install Parakeet runtime (Settings → Speech)"
            )
        }
        if !isModelReady(model) {
            return ModelReadyStatus(
                ready: false,
                message: "Download \(model.displayName) via Install Parakeet"
            )
        }
        do {
            try await ensureWorker(model: model)
            return ModelReadyStatus(ready: true, message: "\(model.displayName) ready")
        } catch {
            return ModelReadyStatus(ready: false, message: error.localizedDescription)
        }
    }

    func transcribe(
        audioURL: URL,
        model: ParakeetModel,
        mode: DictationMode,
        language: String
    ) async throws -> String {
        if mode == .translate {
            throw ParakeetError.translateUnsupported
        }
        guard isRuntimeInstalled() else { throw ParakeetError.runtimeMissing }
        guard isModelReady(model) else { throw ParakeetError.modelMissing(model.displayName) }

        // Ensure 16 kHz mono wav (same helper path as capture)
        let wav = try await ensureWav(audioURL)

        try await ensureWorker(model: model)
        let response = try await send(cmd: [
            "cmd": "transcribe",
            "path": wav.path
        ])
        if wav.path != audioURL.path {
            try? FileManager.default.removeItem(at: wav)
        }

        guard let ok = response["ok"] as? Bool, ok else {
            let err = response["error"] as? String ?? "unknown error"
            throw ParakeetError.workerFailed(err)
        }
        let text = (response["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw ParakeetError.emptyOutput }
        return text
    }

    func warm(model: ParakeetModel) async {
        _ = await ensureReady(model: model)
    }

    func shutdown() {
        if let stdin {
            let payload = (try? JSONSerialization.data(withJSONObject: ["cmd": "quit"])) ?? Data()
            if var line = String(data: payload, encoding: .utf8) {
                line += "\n"
                stdin.write(line.data(using: .utf8) ?? Data())
            }
        }
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        ready = false
        loadedModel = nil
    }

    // MARK: - Worker lifecycle

    private func ensureWorker(model: ParakeetModel) async throws {
        if ready, loadedModel == model, process?.isRunning == true {
            return
        }
        shutdown()
        try await startWorker(model: model)
    }

    private func startWorker(model: ParakeetModel) async throws {
        guard FileManager.default.isExecutableFile(atPath: venvPython.path) else {
            throw ParakeetError.runtimeMissing
        }
        guard FileManager.default.fileExists(atPath: workerScript.path) else {
            throw ParakeetError.runtimeMissing
        }

        let proc = Process()
        proc.executableURL = venvPython
        proc.arguments = [workerScript.path]
        // Prefer HF cache (setup downloads there). Only pass local path if it has real weights.
        let local = modelDir(model)
        let hasLocalWeights: Bool = {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: local.path) else { return false }
            return files.contains { $0.hasSuffix(".onnx") }
        }()
        var env = ProcessInfo.processInfo.environment
        env["PARAKEET_MODEL"] = model.onnxAsrName
        env["PARAKEET_QUANT"] = "int8"
        env["PYTHONUNBUFFERED"] = "1"
        // Prefer existing HF cache (setup may have used ~/models/huggingface)
        if env["HF_HOME"] == nil || env["HF_HOME"]?.isEmpty == true {
            let defaultHF = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("models/huggingface").path
            if FileManager.default.fileExists(atPath: defaultHF) {
                env["HF_HOME"] = defaultHF
            } else {
                env["HF_HOME"] = supportDir.appendingPathComponent("hf-cache").path
            }
        }
        if hasLocalWeights {
            env["PARAKEET_MODEL_PATH"] = local.path
        }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        process = proc
        stdin = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading
        loadedModel = model
        ready = false

        // Wait for ready line (model load can take a while first time)
        let readyLine = try await readLine(timeout: 180)
        guard let ok = readyLine["ok"] as? Bool, ok,
              (readyLine["event"] as? String) == "ready" else {
            let err = readyLine["error"] as? String ?? "worker did not become ready"
            shutdown()
            throw ParakeetError.workerFailed(err)
        }
        ready = true
    }

    private func send(cmd: [String: Any]) async throws -> [String: Any] {
        guard let stdin, ready else { throw ParakeetError.workerFailed("worker not ready") }
        let data = try JSONSerialization.data(withJSONObject: cmd)
        var line = String(data: data, encoding: .utf8) ?? "{}"
        line += "\n"
        stdin.write(line.data(using: .utf8) ?? Data())
        return try await readLine(timeout: 60)
    }

    private func readLine(timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdout else { throw ParakeetError.workerFailed("no stdout") }
        let handle = stdout
        let proc = process

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let deadline = Date().addingTimeInterval(timeout)
                var buffer = Data()
                while Date() < deadline {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        if proc?.isRunning == false {
                            cont.resume(throwing: ParakeetError.workerFailed("worker exited"))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.02)
                        continue
                    }
                    buffer.append(chunk)
                    if let range = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<range)
                        buffer.removeSubrange(buffer.startIndex...range)
                        if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                            cont.resume(returning: obj)
                            return
                        }
                        cont.resume(throwing: ParakeetError.workerFailed("invalid JSON from worker"))
                        return
                    }
                }
                cont.resume(throwing: ParakeetError.timeout)
            }
        }
    }

    private func ensureWav(_ url: URL) async throws -> URL {
        let name = url.lastPathComponent
        if name.hasPrefix("notfluid-16k-"), name.hasSuffix(".wav") {
            return url
        }
        let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        guard let ffmpeg = ffmpegCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return url
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("notfluid-16k-\(UUID().uuidString).wav")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", url.path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            out.path
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) {
            return out
        }
        return url
    }
}
