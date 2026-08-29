import Foundation
import Hummingbird

enum SSHStatusRoutes {
    static func register<Reader, Checker>(
        on router: Router<BasicRequestContext>,
        reader: Reader,
        checker: Checker
    ) where Reader: ContainerReading, Checker: SSHReadinessChecking {
        router.get("/api/v1/containers/:containerId/ssh") { _, context in
            let id = try context.parameters.require("containerId")
            let detail = try await reader.containerDetail(id: id)
            let connection = detail.summary.ssh
            let state: ContainerSSHState
            if let connection {
                switch detail.summary.state {
                case .running:
                    state = await checker.receivesSSHBanner(port: connection.hostPort)
                        ? .ready : .initializing
                case .error:
                    state = .failed
                default:
                    state = .stopped
                }
            } else {
                state = .notConfigured
            }
            return try makeJSONResponse(ContainerSSHStatus(
                containerID: detail.summary.id,
                state: state,
                connection: connection,
                observedAt: Date()
            ))
        }
    }
}
