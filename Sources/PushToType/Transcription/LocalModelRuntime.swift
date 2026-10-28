import Foundation
import PushToTypeSupport

enum LocalModelError: LocalizedError {
    case runtimeMissing(String)
    case modelMissing(String)
    case englishOnly(String)
    case emptyOutput(String)
    case workerFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing(let message), .modelMissing(let message), .englishOnly(let message),
             .emptyOutput(let message), .workerFailed(let message):
            return message
        }
    }
}

enum BundledScript {
    static func url(named name: String) -> URL? {
        let file = name.hasSuffix(".py") || name.hasSuffix(".sh") || name.hasSuffix(".txt") ? name : name
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent(file))
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(root.appendingPathComponent("Resources").appendingPathComponent(file))
        candidates.append(root.appendingPathComponent("scripts").appendingPathComponent(file))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum LocalPythonWorker {
    static func makeProcess(python: URL, script: URL, environment: [String: String]) throws -> (Process, FileHandle, FileHandle) {
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        try process.run()
        return (process, input.fileHandleForWriting, output.fileHandleForReading)
    }
}
