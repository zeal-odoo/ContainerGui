import Hummingbird

enum ContainerReadRoutes {
    static func register<Reader: ContainerReading>(
        on router: Router<BasicRequestContext>,
        reader: Reader
    ) {
        router.get("/api/v1/system/health") { _, _ in
            try makeJSONResponse(try await reader.systemHealth())
        }
        router.get("/api/v1/containers") { _, _ in
            try makeJSONResponse(try await reader.listContainers())
        }
        router.get("/api/v1/containers/:containerId") { _, context in
            let id = try context.parameters.require("containerId")
            return try makeJSONResponse(try await reader.containerDetail(id: id))
        }
    }
}
