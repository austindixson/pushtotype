import Foundation
import NotFluidSupport

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
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func localURL(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.ggmlFileName)
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    func localS1MiniURL() -> URL {
        modelsDirectory.appendingPathComponent(S1Mini.modelFileName)
    }

    func isS1MiniDownloaded() -> Bool {
        let path = localS1MiniURL().path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 100_000_000
    }

    func download(_ model: WhisperModel) async throws {
        try await download(
            from: model.downloadURL,
            dest: localURL(for: model),
            fileName: model.ggmlFileName,
            displayName: model.displayName
        )
    }

    func downloadS1Mini() async throws {
        if isS1MiniDownloaded() {
            status = "\(S1Mini.displayName) already downloaded"
            progress = 1
            return
        }
        try await download(
            from: S1Mini.downloadURL,
            dest: localS1MiniURL(),
            fileName: S1Mini.modelFileName,
            displayName: "\(S1Mini.displayName) by \(S1Mini.vendorName)"
        )
    }

    private func download(from url: URL, dest: URL, fileName: String, displayName: String) async throws {
        if FileManager.default.fileExists(atPath: dest.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size > 100_000_000 {
                status = "\(displayName) already downloaded"
                progress = 1
                return
            }
        }
        isDownloading = true
        progress = 0
        lastError = nil
        status = "Downloading \(fileName)…"

        defer { isDownloading = false }

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
                                    // Project Models symlink convenience
                                    let home = FileManager.default.homeDirectoryForCurrentUser
                                    for rel in ["Desktop/PushToType/Models/\(fileName)", "Desktop/n0tfluid/Models/\(fileName)"] {
                                        let project = home.appendingPathComponent(rel)
                                        try? FileManager.default.createDirectory(
                                            at: project.deletingLastPathComponent(),
                                            withIntermediateDirectories: true
                                        )
                                        try? FileManager.default.removeItem(at: project)
                                        try? FileManager.default.createSymbolicLink(at: project, withDestinationURL: dest)
                                    }
                                    self.status = "\(displayName) ready"
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
            var request = URLRequest(url: url)
            request.setValue("n0tfluid/0.2", forHTTPHeaderField: "User-Agent")
            let t = session.downloadTask(with: request)
            self.task = t
            t.resume()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isDownloading = false
        status = "Cancelled"
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
