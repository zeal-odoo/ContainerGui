import Darwin
import Foundation

enum AILogWorker {
    static let maximumLineBytes = 32_768

    struct Request: Decodable {
        let id: String
        let evidence: String
        let language: String
    }

    private struct Ready: Encodable { let event = "ready" }

    private struct Response: Encodable {
        let id: String
        var text = ""
        var inputTokens = 0
        var outputTokens = 0
        var elapsedSeconds = 0.0
        var error: String?
    }

    enum Failure: Error { case invalidRequest, lineTooLong, readFailed }

    /// Called only by the executable's private child-process entry point.
    static func run(modelDirectory: URL) -> Int32 {
        let parent = getppid()
        guard parent > 1 else { return 1 }
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ContainerGUI.ai.parent-watch", qos: .utility))
        watchdog.schedule(deadline: .now(), repeating: 1)
        watchdog.setEventHandler {
            if getppid() != parent { _exit(0) }
        }
        watchdog.resume()
        defer { watchdog.cancel() }
        do {
            let model = try autoreleasepool { try QwenLogModel(directory: modelDirectory) }
            try emit(Ready())
            let reader = LineReader(handle: .standardInput)
            while let line = try reader.next() {
                let request = try decodeRequest(line)
                let response: Response = autoreleasepool {
                    do {
                        let answer = try model.analyse(evidence: request.evidence, language: request.language)
                        return Response(id: request.id, text: answer.text, inputTokens: answer.inputTokens, outputTokens: answer.outputTokens, elapsedSeconds: answer.elapsedSeconds)
                    } catch {
                        return Response(id: request.id, error: safeCode(error))
                    }
                }
                try emit(response)
            }
            return 0
        } catch {
            try? emit(Response(id: "", error: safeCode(error)))
            return 1
        }
    }

    static func decodeRequest(_ data: Data) throws -> Request {
        guard data.count <= maximumLineBytes,
              let request = try? JSONDecoder().decode(Request.self, from: data),
              !request.id.isEmpty, request.id.utf8.count <= 128,
              request.language == "zh" || request.language == "en",
              !request.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidRequest
        }
        return request
    }

    private static func safeCode(_ error: Error) -> String {
        if let failure = error as? QwenLogModel.Failure { return failure.rawValue }
        if error is QwenTokenizer.Failure { return "tokenizer_invalid" }
        if error is Failure { return "worker_protocol_invalid" }
        return "model_runtime_failed"
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count < maximumLineBytes else { throw Failure.lineTooLong }
        try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    }

    final class LineReader {
        private let handle: FileHandle
        private let maximumBytes: Int
        private var buffer = Data()

        init(handle: FileHandle, maximumBytes: Int = AILogWorker.maximumLineBytes) {
            self.handle = handle
            self.maximumBytes = maximumBytes
        }

        func next() throws -> Data? {
            while true {
                if let newline = buffer.firstIndex(of: 10) {
                    let length = buffer.distance(from: buffer.startIndex, to: newline)
                    guard length <= maximumBytes else { throw Failure.lineTooLong }
                    let line = Data(buffer.prefix(length))
                    buffer.removeFirst(length + 1)
                    return line
                }
                guard buffer.count <= maximumBytes else { throw Failure.lineTooLong }
                // FileHandle.read(upToCount:) can wait for the full count on a pipe.
                // A single read returns the available request while the writer stays open.
                var bytes = [UInt8](repeating: 0, count: min(4096, maximumBytes + 1 - buffer.count))
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw Failure.readFailed
                }
                if count == 0 {
                    guard !buffer.isEmpty else { return nil }
                    defer { buffer.removeAll(keepingCapacity: false) }
                    return Data(buffer)
                }
                buffer.append(contentsOf: bytes.prefix(count))
            }
        }
    }
}
