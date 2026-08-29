import Foundation
import Hummingbird

struct ErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as any HTTPResponseError where error.status == .notFound {
            return addSecurityHeaders(to: makeProblemResponse(ProblemDetail(code: .targetNotFound)))
        } catch {
            return addSecurityHeaders(to: makeProblemResponse(error.containerGUIProblem))
        }
    }
}

func makeProblemResponse(_ problem: ProblemDetail) -> Response {
    let body = (try? JSONEncoder.containerGUI.encode(problem)) ?? Data()
    return Response(
        status: HTTPResponse.Status(code: problem.status),
        headers: [.contentType: "application/problem+json; charset=utf-8"],
        body: .init(byteBuffer: ByteBuffer(data: body))
    )
}

func makeJSONResponse<T: Encodable>(
    _ value: T,
    status: HTTPResponse.Status = .ok,
    headers: HTTPFields = [:]
) throws -> Response {
    var headers = headers
    headers[.contentType] = "application/json; charset=utf-8"
    return Response(
        status: status,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(data: try JSONEncoder.containerGUI.encode(value)))
    )
}
