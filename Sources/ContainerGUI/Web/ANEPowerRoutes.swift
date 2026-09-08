import Hummingbird

enum ANEPowerRoutes {
    static func register(on router: Router<BasicRequestContext>, sampler: ANEPowerSampler) {
        router.get("/api/v1/system/ane") { _, _ in
            try makeJSONResponse(await sampler.snapshot())
        }
    }
}
