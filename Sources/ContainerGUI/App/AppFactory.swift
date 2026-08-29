import Foundation
import Hummingbird
import Logging

enum AppFactory {
    static var publicDirectoryURL: URL {
        Bundle.module.url(forResource: "Public", withExtension: nil)!
    }

    static func makeRouter(configuration: AppConfiguration) -> Router<BasicRequestContext> {
        let executableURL: URL?
        let unavailableCompatibility: CLICompatibility
        do {
            executableURL = try CLIVersionResolver().resolve(explicitPath: configuration.explicitCLIPath)
            unavailableCompatibility = .missing
        } catch CLIResolutionError.notExecutable {
            executableURL = nil
            unavailableCompatibility = .notExecutable
        } catch {
            executableURL = nil
            unavailableCompatibility = .missing
        }
        let reader = ContainerCLIClient(
            executor: FoundationProcessExecutor(),
            executableURL: executableURL,
            unavailableCompatibility: unavailableCompatibility,
            queryTimeout: configuration.queryTimeout,
            mutationTimeout: configuration.mutationTimeout,
            imagePullTimeout: configuration.imagePullTimeout,
            maximumOutputBytes: configuration.maximumCommandOutputBytes
        )
        let router = makeRouter(configuration: configuration, reader: reader)
        ContainerMetricsRoutes.register(
            on: router,
            reader: reader,
            timeout: configuration.queryTimeout
        )
        let coordinator = OperationCoordinator(
            maximumConcurrentMutations: configuration.maximumConcurrentMutations,
            maximumOperationRecords: configuration.maximumOperationRecords,
            operationTTL: configuration.operationTTL
        )
        let controlService = ContainerControlService(controller: reader, coordinator: coordinator)
        let imageService = ImageMutationService(manager: reader, coordinator: coordinator)
        let creationService = ContainerCreationService(manager: reader, coordinator: coordinator)
        OperationRoutes.register(on: router, coordinator: coordinator)
        ResourceMutationRoutes.registerImages(on: router, reader: reader, service: imageService)
        ResourceMutationRoutes.registerCreation(on: router, service: creationService)
        RegistrySearchRoutes.register(
            on: router,
            searcher: RegistrySearchClient(
                transport: FoundationRegistryHTTPTransport(
                    timeoutSeconds: configuration.registryTimeoutSeconds
                ),
                maximumResponseBytes: configuration.maximumRegistryResponseBytes
            )
        )
        ContainerControlRoutes.registerControl(on: router, service: controlService)
        ContainerControlRoutes.registerLogs(
            on: router,
            reader: reader,
            limiter: LogSessionLimiter(maximumSessions: configuration.maximumLogSessions)
        )
        return router
    }

    static func makeRouter<Reader: ContainerReading>(
        configuration: AppConfiguration,
        reader: Reader
    ) -> Router<BasicRequestContext> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(
            SafetyMiddleware(
                policy: RequestSafetyPolicy(
                    expectedOrigin: configuration.origin,
                    maximumBodyBytes: configuration.maximumRequestBodyBytes
                )
            )
        )

        router.get("/api/v1") { _, _ in
            ["name": "Container GUI", "version": AppVersion.current]
        }
        ContainerReadRoutes.register(on: router, reader: reader)

        router.middlewares.add(
            FileMiddleware(publicDirectoryURL.path, searchForIndexHtml: true)
        )
        return router
    }

    static func makeApplication(configuration: AppConfiguration) -> Application<RouterResponder<BasicRequestContext>> {
        let router = makeRouter(configuration: configuration)
        return Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: "ContainerGUI"
            ),
            logger: Logger(label: "ContainerGUI")
        )
    }
}
