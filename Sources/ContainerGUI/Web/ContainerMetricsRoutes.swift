import Hummingbird

enum ContainerMetricsRoutes {
    static func register<Reader: ContainerMetricsReading>(
        on router: Router<BasicRequestContext>,
        reader: Reader
    ) {
        router.get("/api/v1/containers/metrics") { _, _ in
            try makeJSONResponse(try await reader.containerMetrics())
        }
    }
}
