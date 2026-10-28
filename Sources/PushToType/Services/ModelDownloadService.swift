import CryptoKit
import Foundation
import PushToTypeSupport

/// Downloads whisper.cpp ggml weights into Application Support.
@MainActor
final class ModelDownloadService: ObservableObject {
    static let shared = ModelDownloadService()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var status = "Idle"
    @Published var lastError: String?

    private var task: URLSessionDownloadTask?

    var modelsDirectory: URL {
        let dir = AppSupport.directory().appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func localURL(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.ggmlFileName)
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    func download(_ model: WhisperModel) async throws {
        if isDownloaded(model) {
            status = "\(model.displayName) already downloaded"
            progress = 1
            return
        }
        isDownloading = true
        progress = 0
        lastError = nil
        status = "Downloading \(model.displayName) · \(model.downloadSizeLabel)…"

        defer { isDownloading = false }

        let dest = localURL(for: model)
        let tmp = dest.appendingPathExtension("download")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let session = URLSession(
                configuration: .default,
                delegate: DownloadDelegate(
                    progress: { [weak self] p in
                        Task { @MainActor in
                            self?.progress = p
                            self?.status = String(format: "Downloading… %.0f%%", p * 100)
                        }
                    },
                    completion: { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let url):
                                do {
                                    if FileManager.default.fileExists(atPath: dest.path) {
                                        try FileManager.default.removeItem(at: dest)
                                    }
                                    try FileManager.default.moveItem(at: url, to: dest)
                                    try self.verifyChecksum(model, at: dest)
                                    self.status = "\(model.displayName) ready · \(model.downloadSizeLabel)"
                                    self.progress = 1
                                    cont.resume()
                                } catch {
                                    self.lastError = error.localizedDescription
                                    self.status = "Save failed"
                                    cont.resume(throwing: error)
                                }
                            case .failure(let error):
                                self.lastError = error.localizedDescription
                                self.status = "Download failed"
                                cont.resume(throwing: error)
                            }
                        }
                    }
                ),
                delegateQueue: nil
            )
            var request = URLRequest(url: model.downloadURL)
            request.setValue("PushToType/1.0", forHTTPHeaderField: "User-Agent")
            let t = session.downloadTask(with: request)
            self.task = t
            t.resume()
        }
        _ = tmp
    }

    func cancel() {
        task?.cancel()
        task = nil
        isDownloading = false
        status = "Cancelled"
    }

    private func verifyChecksum(_ model: WhisperModel, at url: URL) throws {
        let digest = try FileHash.sha256(of: url)
        guard digest == model.sha256 else {
            try? FileManager.default.removeItem(at: url)
            throw ChecksumMismatch(model: model.displayName)
        }
    }
}

private struct ChecksumMismatch: LocalizedError {
    var model: String
    var errorDescription: String? { "\(model) download did not match its checksum" }
}

private enum FileHash {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void

    init(progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notfluid-model-\(UUID().uuidString).bin")
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            completion(.success(tmp))
        } catch {
            completion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion(.failure(error))
        }
    }
}
