import Hummingbird

enum DiskHealthRoutes {
    static func register(on router: Router<BasicRequestContext>, service: DiskHealthService) {
        router.get("/api/v1/system/disks") { _, _ in
            try makeJSONResponse(await service.snapshot())
        }
    }
}
