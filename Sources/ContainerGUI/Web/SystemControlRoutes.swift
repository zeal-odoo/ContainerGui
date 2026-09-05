import Foundation
import Hummingbird
import HTTPTypes

enum SystemControlRoutes {
    static func register<Controller: SystemControlling>(
        on router: Router<BasicRequestContext>,
        service: SystemControlService<Controller>
    ) {
        router.post("/api/v1/system/start") { request, context in
            guard let key = request.headers[HTTPField.Name("Idempotency-Key")!],
                  UUID(uuidString: key) != nil else {
                throw ProblemDetail(code: .validationFailed, fieldErrors: ["Idempotency-Key": "必须为 UUID"])
            }
            guard let body = try? await request.decode(as: [String: JSONValue].self, context: context),
                  body.isEmpty else {
                throw ProblemDetail(code: .validationFailed, fieldErrors: ["body": "请求必须为空 JSON 对象"])
            }
            let operation = try await service.submitStart(idempotencyKey: key)
            return try makeJSONResponse(
                operation,
                status: .accepted,
                headers: [.location: "/api/v1/operations/\(operation.id.uuidString)"]
            )
        }
    }
}
