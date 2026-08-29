import Foundation
import Hummingbird
import HTTPTypes

private struct ConfirmedTargetRequest: Decodable {
    let confirmationTarget: String
}

enum ContainerControlRoutes {
    private static let idempotencyName = HTTPField.Name("Idempotency-Key")!

    static func registerControl<Controller: ContainerControlling>(
        on router: Router<BasicRequestContext>,
        service: ContainerControlService<Controller>
    ) {
        router.post("/api/v1/containers/:containerId/start") { request, context in
            let id = try validContainerID(context.parameters.require("containerId"))
            let key = try idempotencyKey(request)
            let operation = try await service.submitStart(id: id, idempotencyKey: key)
            return try accepted(operation)
        }
        router.post("/api/v1/containers/:containerId/stop") { request, context in
            let id = try validContainerID(context.parameters.require("containerId"))
            let key = try idempotencyKey(request)
            let body: ConfirmedTargetRequest
            do {
                body = try await request.decode(as: ConfirmedTargetRequest.self, context: context)
            } catch {
                throw ProblemDetail(code: .validationFailed, fieldErrors: ["confirmationTarget": "必须提供确认目标"])
            }
            let operation = try await service.submitStop(
                id: id,
                confirmationTarget: body.confirmationTarget,
                idempotencyKey: key
            )
            return try accepted(operation)
        }
    }

    static func registerLogs<Reader: ContainerLogReading>(
        on router: Router<BasicRequestContext>,
        reader: Reader,
        limiter: LogSessionLimiter
    ) {
        router.get("/api/v1/containers/:containerId/logs") { request, context in
            let id = try validContainerID(context.parameters.require("containerId"))
            let tail = try tailLines(request)
            return try makeJSONResponse(try await reader.recentLogs(id: id, tail: tail))
        }
        router.get("/api/v1/containers/:containerId/logs/stream") { request, context in
            let id = try validContainerID(context.parameters.require("containerId"))
            let tail = try tailLines(request)
            let token = try await limiter.acquire()
            do {
                let source = try await reader.followLogs(id: id, tail: tail)
                let stream = LogEventStream.make(
                    source: source,
                    onTermination: { await limiter.release(token) }
                )
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream; charset=utf-8",
                        .cacheControl: "no-cache",
                    ],
                    body: .init(asyncSequence: stream)
                )
            } catch {
                await limiter.release(token)
                throw error
            }
        }
    }

    private static func accepted(_ operation: Operation) throws -> Response {
        try makeJSONResponse(
            operation,
            status: .accepted,
            headers: [.location: "/api/v1/operations/\(operation.id.uuidString)"]
        )
    }

    private static func idempotencyKey(_ request: Request) throws -> String {
        guard let value = request.headers[idempotencyName], UUID(uuidString: value) != nil else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: ["Idempotency-Key": "必须为 UUID"])
        }
        return value
    }

    private static func validContainerID(_ id: String) throws -> String {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: ["containerId": "容器标识无效"])
        }
        return id
    }

    private static func tailLines(_ request: Request) throws -> Int {
        guard let raw = request.uri.queryParameters["tail"] else { return 200 }
        guard let tail = Int(raw), (0...10_000).contains(tail) else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: ["tail": "必须在 0...10000 之间"])
        }
        return tail
    }
}
