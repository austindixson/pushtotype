import Foundation

/// S1-mini by Superwhisper — 0.6B on-device normalizer for raw ASR text.
/// Apache 2.0 plus a naming clause: keep the name "S1-mini" by "Superwhisper".
public enum S1MiniStyling: String, CaseIterable, Sendable {
    case casual
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal

    public var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .semiCasual: return "Semi-casual"
        case .semiFormal: return "Semi-formal"
        case .formal: return "Formal"
        }
    }
}

public enum S1MiniStructure: String, Sendable {
    case prose
    case lists
}

public enum S1MiniContext: String, Sendable {
    case general
    case email
}

public struct S1MiniControls: Sendable {
    public var styling: S1MiniStyling
    public var structure: S1MiniStructure
    public var context: S1MiniContext

    public init(
        styling: S1MiniStyling = .semiFormal,
        structure: S1MiniStructure = .prose,
        context: S1MiniContext = .general
    ) {
        self.styling = styling
        self.structure = structure
        self.context = context
    }

    public static func context(forBundleID bundleID: String?) -> S1MiniContext {
        let id = (bundleID ?? "").lowercased()
        let emailHints = ["mail", "outlook", "spark", "airmail", "superhuman", "hey.com", "proton"]
        if emailHints.contains(where: { id.contains($0) }) { return .email }
        return .general
    }
}

public enum S1MiniError: LocalizedError, Sendable {
    case binaryMissing
    case modelMissing
    case serverFailed(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "llama-server not found. Run: brew install llama.cpp"
        case .modelMissing:
            return "S1-mini model missing. Download it from Settings → Speech."
        case .serverFailed(let msg):
            return "S1-mini server failed: \(msg)"
        case .requestFailed(let msg):
            return "S1-mini request failed: \(msg)"
        }
    }
}

public enum S1Mini {
    public static let displayName = "S1-mini"
    public static let vendorName = "Superwhisper"
    public static let modelFileName = "s1-mini-q4_k_m.gguf"
    public static let downloadURL = URL(
        string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf"
    )!
    public static let expectedBytes: Int64 = 484_219_808
    public static let systemPrompt =
        "You are a text normalizer for speech-to-text transcripts. The input begins "
        + "with a control line specifying the styling, structure, and context settings; "
        + "clean the transcript to match those settings and output only the cleaned text."

    public static func controlLine(_ controls: S1MiniControls) -> String {
        "[Styling: \(controls.styling.rawValue)] [Structure: \(controls.structure.rawValue)] [Context: \(controls.context.rawValue)]"
    }

    public static func userMessage(_ transcript: String, controls: S1MiniControls) -> String {
        "\(controlLine(controls))\n\(transcript)"
    }

    public static func maxNewTokens(for transcript: String) -> Int {
        let approx = max(8, transcript.utf8.count / 4)
        return min(1024, Int(Double(approx) * 1.3) + 32)
    }
}

/// Persistent llama.cpp server wrapping S1-mini (GGUF).
///
/// Input format is part of the model: system prompt + control line + raw transcript.
/// Thinking must stay off or the model returns an empty `<think>` block.
public actor S1MiniService {
    public static let shared = S1MiniService()

    private static let preferredPort = 18_765
    private static let healthPath = "/health"

    private var process: Process?
    private var port: Int = S1MiniService.preferredPort
    private var ready = false
    private var stderrData = Data()

    public init() {}

    public func isBinaryAvailable() -> Bool {
        resolveServerBinary() != nil
    }

    public func isModelDownloaded() -> Bool {
        modelURL() != nil
    }

    public func modelURL() -> URL? {
        let candidates: [URL] = [
            modelsDirectory().appendingPathComponent(S1Mini.modelFileName),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/PushToType/Models/\(S1Mini.modelFileName)"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/n0tfluid/Models/\(S1Mini.modelFileName)")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            if size > 100_000_000 { return url }
        }
        return nil
    }

    public func ensureReady() async -> (ready: Bool, message: String) {
        guard resolveServerBinary() != nil || resolveCLIBinary() != nil else {
            return (false, "Install llama.cpp: brew install llama.cpp")
        }
        guard modelURL() != nil else {
            return (false, "Download \(S1Mini.displayName) (~462 MB) in Settings → Speech")
        }
        do {
            try await ensureServer()
            return (true, "\(S1Mini.displayName) by \(S1Mini.vendorName) ready")
        } catch {
            // CLI one-shot is enough to report "model present" even if the server fails
            if resolveCLIBinary() != nil {
                return (true, "\(S1Mini.displayName) ready (CLI)")
            }
            return (false, error.localizedDescription)
        }
    }

    public func warm() async {
        _ = await ensureReady()
        if ready {
            _ = try? await normalize("um", controls: S1MiniControls())
        }
    }

    public func normalize(_ raw: String, controls: S1MiniControls = S1MiniControls()) async throws -> String {
        let transcript = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return "" }

        do {
            _ = try await ensureServer()
            return try await requestNormalize(transcript, controls: controls)
        } catch {
            return try await cliNormalize(transcript, controls: controls)
        }
    }

    public func shutdown() {
        process?.terminate()
        process = nil
        ready = false
    }

    // MARK: - Server

    @discardableResult
    private func ensureServer() async throws -> Int {
        if ready, let proc = process, proc.isRunning {
            return port
        }
        if await healthOK(port: Self.preferredPort) {
            port = Self.preferredPort
            ready = true
            return port
        }
        try await startServer()
        return port
    }

    private func startServer() async throws {
        shutdown()
        guard let binary = resolveServerBinary() else { throw S1MiniError.binaryMissing }
        guard let model = modelURL() else { throw S1MiniError.modelMissing }

        port = Self.preferredPort
        if await healthOK(port: port) {
            ready = true
            return
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = [
            "-m", model.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--jinja",
            "--chat-template-kwargs", "{\"enable_thinking\":false}",
            "--temp", "0",
            "--ctx-size", "2048",
            "--log-disable"
        ]
        var env = ProcessInfo.processInfo.environment
        let extras = ["/opt/homebrew/bin", "/usr/local/bin"]
        let path = env["PATH"] ?? ""
        env["PATH"] = (extras + [path]).joined(separator: ":")
        proc.environment = env

        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        stderrData = Data()
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { await self.appendStderr(chunk) }
        }

        do {
            try proc.run()
        } catch {
            throw S1MiniError.serverFailed(error.localizedDescription)
        }
        process = proc

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if !proc.isRunning {
                let errText = String(data: stderrData, encoding: .utf8) ?? ""
                throw S1MiniError.serverFailed(errText.isEmpty ? "llama-server exited" : errText)
            }
            if await healthOK(port: port) {
                ready = true
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        shutdown()
        throw S1MiniError.serverFailed("Timed out waiting for llama-server on port \(port)")
    }

    private func appendStderr(_ chunk: Data) {
        stderrData.append(chunk)
        if stderrData.count > 32_768 {
            stderrData = stderrData.suffix(16_384)
        }
    }

    private func healthOK(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(Self.healthPath)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func requestNormalize(_ transcript: String, controls: S1MiniControls) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw S1MiniError.requestFailed("bad URL")
        }
        let payload: [String: Any] = [
            "temperature": 0,
            "max_tokens": S1Mini.maxNewTokens(for: transcript),
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": [
                ["role": "system", "content": S1Mini.systemPrompt],
                ["role": "user", "content": S1Mini.userMessage(transcript, controls: controls)]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw S1MiniError.requestFailed("HTTP \(code) \(body.prefix(200))")
        }
        let cleaned = Self.decodeChatContent(data)
        return Self.postProcess(cleaned, fallback: transcript)
    }

    // MARK: - CLI fallback

    private func cliNormalize(_ transcript: String, controls: S1MiniControls) async throws -> String {
        guard let binary = resolveCLIBinary() else { throw S1MiniError.binaryMissing }
        guard let model = modelURL() else { throw S1MiniError.modelMissing }

        let n = S1Mini.maxNewTokens(for: transcript)
        let args = [
            "-m", model.path,
            "--jinja",
            "--chat-template-kwargs", "{\"enable_thinking\":false}",
            "--temp", "0",
            "-st",
            "--no-display-prompt",
            "--simple-io",
            "--log-disable",
            "--no-warmup",
            "-n", "\(n)",
            "-sys", S1Mini.systemPrompt,
            "-p", S1Mini.userMessage(transcript, controls: controls)
        ]
        let result = try await runProcess(binary: binary, arguments: args)
        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw S1MiniError.requestFailed(err.isEmpty ? "llama-cli exited \(result.exitCode)" : err)
        }
        return Self.postProcess(result.stdout, fallback: transcript)
    }

    // MARK: - Paths

    private func modelsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func resolveServerBinary() -> URL? {
        resolveBinary(names: ["llama-server"])
    }

    private func resolveCLIBinary() -> URL? {
        resolveBinary(names: ["llama-cli"])
    }

    private func resolveBinary(names: [String]) -> URL? {
        var paths: [String] = []
        for name in names {
            paths += [
                "/opt/homebrew/bin/\(name)",
                "/usr/local/bin/\(name)",
                NSHomeDirectory() + "/.local/bin/\(name)"
            ]
        }
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for name in names {
            if let found = which(name) { return URL(fileURLWithPath: found) }
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
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
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

    // MARK: - Output

    static func decodeChatContent(_ data: Data) -> String {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first
        else { return "" }
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        if let text = first["text"] as? String { return text }
        return ""
    }

    static func postProcess(_ raw: String, fallback: String) -> String {
        var s = raw
        if let re = try? NSRegularExpression(pattern: #"(?s)<think>.*?</think>"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```"), s.hasSuffix("```") {
            s = String(s.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.isEmpty {
            return looksLikeFillerOnly(fallback) ? "" : fallback
        }
        return s
    }

    static func looksLikeFillerOnly(_ input: String) -> Bool {
        let lowered = input.lowercased()
        let stripped = lowered.replacingOccurrences(
            of: #"\b(um|uh|uhh|erm|hmm|ah|oh|like|you know|i mean|yeah|okay|ok|so)\b"#,
            with: " ",
            options: .regularExpression
        )
        let leftover = stripped.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
        return leftover.count < 3
    }
}
