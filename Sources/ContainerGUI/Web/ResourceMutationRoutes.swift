import Foundation
import Hummingbird
import HTTPTypes

enum ResourceMutationRoutes {
    private static let idempotencyName = HTTPField.Name("Idempotency-Key")!

    static func registerImages<Reader, Manager>(
        on router: Router<BasicRequestContext>,
        reader: Reader,
        service: ImageMutationService<Manager>
    ) where Reader: ImageReading, Manager: ImageReading, Manager: ResourceMutating, Manager: ContainerControlling {
        router.get("/api/v1/images") { _, _ in
            try makeJSONResponse(try await reader.listImages())
        }
        router.post("/api/v1/images/pull") { request, context in
            let key = try idempotencyKey(request)
            let body: ImagePullRequest
            do {
                body = try await request.decode(as: ImagePullRequest.self, context: context)
            } catch let problem as ProblemDetail {
                throw problem
            } catch {
                throw ProblemDetail(
                    code: .validationFailed,
                    fieldErrors: ["body": "请求内容格式无效"]
                )
            }
            let operation = try await service.submitPull(request: body, idempotencyKey: key)
            return try accepted(operation)
        }
        router.post("/api/v1/images/delete") { request, context in
            let key = try idempotencyKey(request)
            let body: ImageDeleteRequest
            do {
                body = try await request.decode(as: ImageDeleteRequest.self, context: context)
            } catch let problem as ProblemDetail {
                throw problem
            } catch {
                throw ProblemDetail(
                    code: .validationFailed,
                    fieldErrors: ["body": "请求内容格式无效"]
                )
            }
            let operation = try await service.submitDelete(request: body, idempotencyKey: key)
            return try accepted(operation)
        }
    }

    static func registerCreation<Manager>(
        on router: Router<BasicRequestContext>,
        service: ContainerCreationService<Manager>
    ) where Manager: ContainerControlling, Manager: ResourceMutating {
        router.post("/api/v1/containers") { request, context in
            let key = try idempotencyKey(request)
            let body: ContainerCreateRequest
            do {
                body = try await request.decode(as: ContainerCreateRequest.self, context: context)
            } catch let problem as ProblemDetail {
                throw problem
            } catch {
                throw ProblemDetail(
                    code: .validationFailed,
                    fieldErrors: ["body": "请求内容格式无效"]
                )
            }
            let operation = try await service.submitCreate(request: body, idempotencyKey: key)
            return try accepted(operation)
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
            throw ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["Idempotency-Key": "必须为 UUID"]
            )
        }
        return value
    }
}
