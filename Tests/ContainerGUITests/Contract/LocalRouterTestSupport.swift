import Hummingbird
import HummingbirdTesting

// Hummingbird's router test client hardcodes "localhost" as the authority.
// Model the configured listener explicitly without weakening production checks.
extension ApplicationProtocol {
    func testLocal<Value>(
        authority: String? = "127.0.0.1:8787",
        _ test: @Sendable (any TestClientProtocol) async throws -> Value
    ) async throws -> Value {
        let responder = try await self.responder
        var app = Application(
            responder: LocalTestResponder(base: responder, authority: authority),
            configuration: configuration,
            services: services,
            logger: logger
        )
        for process in processesRunBeforeServerStart {
            app.beforeServerStarts(perform: process)
        }
        return try await app.test(.router, test)
    }
}

private struct LocalTestResponder<Base: HTTPResponder>: HTTPResponder {
    typealias Context = Base.Context

    let base: Base
    let authority: String?

    func respond(to request: Request, context: Context) async throws -> Response {
        var head = request.head
        head.authority = authority
        return try await base.respond(to: Request(head: head, body: request.body), context: context)
    }
}
