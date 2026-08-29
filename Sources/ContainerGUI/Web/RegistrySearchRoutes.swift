import Hummingbird

enum RegistrySearchRoutes {
    static func register<Searcher: RegistrySearching>(
        on router: Router<BasicRequestContext>,
        searcher: Searcher
    ) {
        router.get("/api/v1/registry-search/repositories") { request, _ in
            let query = try repositoryRequest(request)
            return try makeJSONResponse(try await searcher.searchRepositories(query))
        }
        router.get("/api/v1/registry-search/tags") { request, _ in
            let query = try tagRequest(request)
            return try makeJSONResponse(try await searcher.listTags(query))
        }
    }

    private static func repositoryRequest(_ request: Request) throws -> RemoteRepositorySearchRequest {
        let parameters = request.uri.queryParameters
        let registry = try registry(parameters["registry"].map(String.init))
        let ownerType = try ownerType(parameters["ownerType"].map(String.init))
        let page = try page(parameters["page"].map(String.init))
        return try RemoteRepositorySearchRequest(
            registry: registry,
            query: parameters["query"].map(String.init),
            ownerType: ownerType,
            owner: parameters["owner"].map(String.init),
            page: page
        ).validated()
    }

    private static func tagRequest(_ request: Request) throws -> RemoteTagListRequest {
        let parameters = request.uri.queryParameters
        let registry = try registry(parameters["registry"].map(String.init))
        let ownerType = try ownerType(parameters["ownerType"].map(String.init))
        let page = try page(parameters["page"].map(String.init))
        return try RemoteTagListRequest(
            registry: registry,
            repository: parameters["repository"].map(String.init) ?? "",
            ownerType: ownerType,
            owner: parameters["owner"].map(String.init),
            page: page
        ).validated()
    }

    private static func registry(_ raw: String?) throws -> RemoteRegistry {
        guard let raw, let value = RemoteRegistry(rawValue: raw) else {
            throw ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["registry": "镜像平台必须为 Docker Hub 或 GHCR"]
            )
        }
        return value
    }

    private static func ownerType(_ raw: String?) throws -> GHCRNamespaceType? {
        guard let raw else { return nil }
        guard let value = GHCRNamespaceType(rawValue: raw) else {
            throw ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["ownerType": "GHCR 范围必须为用户或组织"]
            )
        }
        return value
    }

    private static func page(_ raw: String?) throws -> Int {
        guard let raw else { return 1 }
        guard let value = Int(raw), (1...500).contains(value) else {
            throw ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["page": "页码必须在 1...500 之间"]
            )
        }
        return value
    }
}
