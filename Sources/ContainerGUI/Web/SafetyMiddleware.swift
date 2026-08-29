import Hummingbird
import HTTPTypes

struct RequestSafetyPolicy: Sendable {
    let expectedOrigin: String
    let maximumBodyBytes: Int

    func validateMutation(
        origin: String?,
        contentType: String?,
        contentLength: Int?
    ) -> ProblemDetail? {
        guard origin == expectedOrigin else {
            return ProblemDetail(code: .originRejected)
        }
        let mediaType = contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard mediaType == "application/json" else {
            return ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["Content-Type": "必须为 application/json"]
            )
        }
        if let contentLength, contentLength > maximumBodyBytes {
            return ProblemDetail(code: .requestTooLarge)
        }
        return nil
    }
}

struct SafetyMiddleware<Context: RequestContext>: RouterMiddleware {
    let policy: RequestSafetyPolicy

    func handle(
        _ incomingRequest: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var request = incomingRequest
        var response: Response
        if Self.isMutation(request.method) {
            let length = request.headers[.contentLength].flatMap(Int.init)
            if let problem = policy.validateMutation(
                origin: request.headers[.origin],
                contentType: request.headers[.contentType],
                contentLength: length
            ) {
                response = makeProblemResponse(problem)
            } else {
                do {
                    _ = try await request.collectBody(upTo: policy.maximumBodyBytes)
                } catch {
                    return addSecurityHeaders(
                        to: makeProblemResponse(ProblemDetail(code: .requestTooLarge))
                    )
                }
                response = try await next(request, context)
            }
        } else {
            response = try await next(request, context)
        }

        return addSecurityHeaders(to: response)
    }

    private static func isMutation(_ method: HTTPRequest.Method) -> Bool {
        method == .post || method == .put || method == .patch || method == .delete
    }

}

func addSecurityHeaders(to incoming: Response) -> Response {
    var response = incoming
    response.headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
    response.headers[HTTPField.Name("X-Frame-Options")!] = "DENY"
    response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
    response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
    response.headers[.cacheControl] = "no-store"
    return response
}
