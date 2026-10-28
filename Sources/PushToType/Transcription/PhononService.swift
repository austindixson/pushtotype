import Foundation
import PushToTypeSupport

enum PhononRuntime {
    static var supportDir: URL {
        AppSupport.directory().appendingPathComponent("phonon-\(PhononCatalog.packageVersion)", isDirectory: true)
    }

    static var venvPython: URL { supportDir.appendingPathComponent("venv/bin/python") }

    static var modelDir: URL {
        supportDir.appendingPathComponent("models/speech/FermionResearch__Phonon-2/model_phonon2_c4c_int6")
    }

    static var isAvailable: Bool {
        let files = ["config.json", "packed_manifest.json", "model.fermion"]
        let modelReady = files.allSatisfy {
            FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0).path)
        }
        let marker = supportDir.appendingPathComponent("models/ready-\(PhononCatalog.packageVersion)")
        return FileManager.default.isExecutableFile(atPath: venvPython.path)
            && BundledScript.url(named: "phonon_worker.py") != nil
            && modelReady
            && FileManager.default.fileExists(atPath: marker.path)
    }

    static let missingCopy = "Download Phonon 2 in Settings. English, Apple silicon, \(PhononCatalog.model.downloadSizeLabel) plus the local runtime."
}

actor PhononService {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var ready = false

    func ensureReady() -> ModelReadyStatus {
        ModelReadyStatus(
            ready: PhononRuntime.isAvailable,
            message: PhononRuntime.isAvailable ? "Phonon 2 ready · local" : PhononRuntime.missingCopy
        )
    }

    func warm() async {
        guard PhononRuntime.isAvailable else { return }
        do { try await ensureWorker() } catch { shutdown() }
    }

    func transcribe(audioURL: URL, mode: DictationMode, language: String) async throws -> String {
        if mode == .translate || !["en", "auto", ""].contains(language.lowercased()) {
            throw LocalModelError.englishOnly("Phonon 2 transcribes English only. Use Whisper to translate.")
        }
        guard PhononRuntime.isAvailable else { throw LocalModelError.runtimeMissing(PhononRuntime.missingCopy) }
        try await ensureWorker()
        let response = try await send(["cmd": "transcribe", "path": audioURL.path], timeout: 300)
        guard let ok = response["ok"] as? Bool, ok else {
            shutdown()
            throw LocalModelError.workerFailed(response["error"] as? String ?? "Phonon 2 failed")
        }
        let text = (response["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw LocalModelError.emptyOutput("Phonon 2 produced no text") }
        return text
    }

    private func ensureWorker() async throws {
        if ready, process?.isRunning == true { return }
        shutdown()
        guard FileManager.default.isExecutableFile(atPath: PhononRuntime.venvPython.path),
              let script = BundledScript.url(named: "phonon_worker.py") else {
            throw LocalModelError.runtimeMissing(PhononRuntime.missingCopy)
        }
        let (process, stdin, stdout) = try LocalPythonWorker.makeProcess(
            python: PhononRuntime.venvPython,
            script: script,
            environment: [
                "FERMION_CACHE_DIR": PhononRuntime.supportDir.appendingPathComponent("models").path,
                "HF_HOME": PhononRuntime.supportDir.appendingPathComponent("hf-cache").path,
                "HF_HUB_OFFLINE": "1",
                "FERMION_DEVICE": "mlx",
            ]
        )
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        let readyLine = try await read(timeout: 180)
        guard (readyLine["ok"] as? Bool) == true, (readyLine["event"] as? String) == "ready" else {
            let message = readyLine["error"] as? String ?? "Phonon 2 did not start"
            shutdown()
            throw LocalModelError.workerFailed(message)
        }
        ready = true
    }

    private func send(_ command: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdin, ready else { throw LocalModelError.workerFailed("Phonon 2 is not ready") }
        try WorkerPipe.write(command, to: stdin)
        return try await read(timeout: timeout)
    }

    private func read(timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdout else { throw LocalModelError.workerFailed("Phonon 2 pipe closed") }
        let running = process
        do {
            return try await WorkerPipe.readObject(from: stdout, isRunning: { running?.isRunning == true }, timeout: timeout)
        } catch {
            throw LocalModelError.workerFailed("Phonon 2 stopped responding")
        }
    }

    private func shutdown() {
        if process?.isRunning == true { process?.terminate() }
        try? stdin?.close()
        try? stdout?.close()
        process = nil
        stdin = nil
        stdout = nil
        ready = false
    }
}
