import Foundation
import PushToTypeSupport

enum BarkRuntime {
    static var venvPython: URL {
        AppSupport.directory().appendingPathComponent("bark-venv/bin/python")
    }

    static func modelDir(_ model: BarkModel) -> URL {
        AppSupport.directory()
            .appendingPathComponent("Models/bark", isDirectory: true)
            .appendingPathComponent(model.rawValue, isDirectory: true)
    }

    static func isRuntimeInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && BundledScript.url(named: "bark_worker.py") != nil
    }

    static func isModelReady(_ model: BarkModel) -> Bool {
        let file = modelDir(model).appendingPathComponent("model.bark")
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size == model.model.files[0].bytes
    }

    static func missingCopy(_ model: BarkModel) -> String {
        "Download \(model.displayName) in Settings (\(model.model.downloadSizeLabel)). Apple silicon. Audio stays on this Mac."
    }
}

actor BarkService {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var loaded: BarkModel?
    private var ready = false

    func ensureReady(_ model: BarkModel) -> ModelReadyStatus {
        guard BarkRuntime.isRuntimeInstalled() else {
            return ModelReadyStatus(ready: false, message: BarkRuntime.missingCopy(model))
        }
        guard BarkRuntime.isModelReady(model) else {
            return ModelReadyStatus(ready: false, message: BarkRuntime.missingCopy(model))
        }
        return ModelReadyStatus(ready: true, message: "\(model.displayName) ready · \(model.model.downloadSizeLabel)")
    }

    func warm(_ model: BarkModel) async {
        guard BarkRuntime.isModelReady(model) else { return }
        do { try await ensureWorker(model) } catch { shutdown() }
    }

    func transcribe(audioURL: URL, model: BarkModel, mode: DictationMode) async throws -> String {
        if mode == .translate {
            throw LocalModelError.englishOnly("\(model.displayName) does not translate. Use Whisper.")
        }
        guard BarkRuntime.isRuntimeInstalled() else {
            throw LocalModelError.runtimeMissing(BarkRuntime.missingCopy(model))
        }
        guard BarkRuntime.isModelReady(model) else {
            throw LocalModelError.modelMissing(BarkRuntime.missingCopy(model))
        }
        try await ensureWorker(model)
        let response = try await send(["cmd": "transcribe", "path": audioURL.path], timeout: 300)
        guard (response["ok"] as? Bool) == true else {
            shutdown()
            throw LocalModelError.workerFailed(response["error"] as? String ?? "\(model.displayName) failed")
        }
        let text = (response["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw LocalModelError.emptyOutput("\(model.displayName) produced no text") }
        return text
    }

    private func ensureWorker(_ model: BarkModel) async throws {
        if ready, loaded == model, process?.isRunning == true { return }
        shutdown()
        guard let script = BundledScript.url(named: "bark_worker.py") else {
            throw LocalModelError.runtimeMissing(BarkRuntime.missingCopy(model))
        }
        let spec = model.model
        let weight = spec.files[0]
        let (process, stdin, stdout) = try LocalPythonWorker.makeProcess(
            python: BarkRuntime.venvPython,
            script: script,
            environment: [
                "BARK_DIR": BarkRuntime.modelDir(model).path,
                "BARK_REPO": spec.repo,
                "BARK_REVISION": spec.revision,
                "BARK_SHA256": weight.sha256,
                "BARK_URL": spec.fileURL(weight.name).absoluteString,
                "HF_HUB_OFFLINE": "1",
            ]
        )
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        let line = try await read(timeout: 180)
        guard (line["ok"] as? Bool) == true, (line["event"] as? String) == "ready" else {
            shutdown()
            throw LocalModelError.workerFailed(line["error"] as? String ?? "\(model.displayName) did not start")
        }
        loaded = model
        ready = true
    }

    private func send(_ command: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdin, ready else { throw LocalModelError.workerFailed("Bark is not ready") }
        try WorkerPipe.write(command, to: stdin)
        return try await read(timeout: timeout)
    }

    private func read(timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdout else { throw LocalModelError.workerFailed("Bark pipe closed") }
        let running = process
        do {
            return try await WorkerPipe.readObject(from: stdout, isRunning: { running?.isRunning == true }, timeout: timeout)
        } catch {
            throw LocalModelError.workerFailed("Bark stopped responding")
        }
    }

    private func shutdown() {
        if process?.isRunning == true { process?.terminate() }
        try? stdin?.close()
        try? stdout?.close()
        process = nil
        stdin = nil
        stdout = nil
        loaded = nil
        ready = false
    }
}
