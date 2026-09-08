import Foundation
import Hummingbird

enum AILogRoutes {
    static func register(on router: Router<BasicRequestContext>, service: AILogService) {
        router.get("/api/v1/ai/logs/status") { _, _ in
            try await makeJSONResponse(service.status())
        }
        router.post("/api/v1/ai/logs/install") { request, context in
            guard let body = try? await request.decode(as: [String: JSONValue].self, context: context),
                  Set(body.keys) == ["confirmed"], body["confirmed"] == .bool(true) else {
                throw ProblemDetail(code: .confirmationMismatch)
            }
            try await service.install(confirmed: true)
            return try await makeJSONResponse(service.status(), status: .accepted)
        }
        router.post("/api/v1/ai/logs/enable") { request, context in
            guard let body = try? await request.decode(as: [String: JSONValue].self, context: context),
                  Set(body.keys) == ["containerId", "language"],
                  case .string(let id) = body["containerId"],
                  case .string(let language) = body["language"] else {
                throw ProblemDetail(code: .validationFailed)
            }
            try await service.enable(containerID: id, language: language)
            return try await makeJSONResponse(service.status(), status: .accepted)
        }
        for action in ["disable", "analyse", "heartbeat"] {
            router.post("/api/v1/ai/logs/\(action)") { request, context in
                guard let body = try? await request.decode(as: [String: JSONValue].self, context: context), body.isEmpty else {
                    throw ProblemDetail(code: .validationFailed)
                }
                switch action {
                case "disable": try await service.disable()
                case "analyse": await service.analyse()
                default: await service.heartbeat()
                }
                return try await makeJSONResponse(service.status())
            }
        }
    }
}
