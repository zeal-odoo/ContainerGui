import Hummingbird

enum UpdateCheckRoutes {
    static func registerContainer<Checker: UpdateChecking>(
        on router: Router<BasicRequestContext>,
        checker: Checker
    ) {
        router.get("/api/v1/container-update-check") { _, _ in
            try makeJSONResponse(try await checker.checkForUpdates())
        }
    }

    static func register<Checker: UpdateChecking>(
        on router: Router<BasicRequestContext>,
        checker: Checker
    ) {
        router.get("/api/v1/update-check") { _, _ in
            try makeJSONResponse(try await checker.checkForUpdates())
        }
    }
}
