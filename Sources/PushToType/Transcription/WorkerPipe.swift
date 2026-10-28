import Darwin
import Foundation

enum WorkerPipeError: Error {
    case timeout
    case exited
    case invalidJSON
    case failed
}

enum WorkerPipe {
    static func write(_ object: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var line = String(data: data, encoding: .utf8) ?? "{}"
        line += "\n"
        try handle.write(contentsOf: Data(line.utf8))
    }

    static func readObject(
        from handle: FileHandle,
        isRunning: @escaping @Sendable () -> Bool,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let result = await Task.detached(priority: .userInitiated) {
            collect(from: handle, isRunning: isRunning, timeout: timeout)
        }.value
        return try result.get()
    }

    private static func collect(
        from handle: FileHandle,
        isRunning: @Sendable () -> Bool,
        timeout: TimeInterval
    ) -> Result<[String: Any], WorkerPipeError> {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            switch readChunk(from: handle, isRunning: isRunning) {
            case .waiting:
                continue
            case .failed:
                return .failure(.failed)
            case .exited:
                return .failure(.exited)
            case .data(let chunk):
                if let done = takeLine(chunk, buffer: &buffer) {
                    return done
                }
            }
        }
        return .failure(.timeout)
    }

    private enum Chunk {
        case waiting
        case data(Data)
        case exited
        case failed
    }

    private static func readChunk(from handle: FileHandle, isRunning: () -> Bool) -> Chunk {
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let polled = poll(&descriptor, 1, 100)
        if polled == 0 { return .waiting }
        if polled < 0 { return errno == EINTR ? .waiting : .failed }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
        if count < 0 { return errno == EINTR ? .waiting : .failed }
        if count == 0 { return isRunning() ? .waiting : .exited }
        return .data(Data(bytes.prefix(count)))
    }

    private static func takeLine(_ chunk: Data, buffer: inout Data) -> Result<[String: Any], WorkerPipeError>? {
        buffer.append(chunk)
        guard buffer.count <= 4_194_304 else { return .failure(.failed) }
        guard let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<newline)
        buffer.removeSubrange(buffer.startIndex...newline)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        return .success(object)
    }
}
