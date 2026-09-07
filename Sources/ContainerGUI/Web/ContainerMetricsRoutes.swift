import Hummingbird

enum ContainerMetricsRoutes {
    static func register<Reader: ContainerMetricsReading>(
        on router: Router<BasicRequestContext>,
        reader: Reader,
        timeout: Duration = .seconds(5),
        hostCapacity: HostResourceCapacity = .current
    ) {
        router.get("/api/v1/containers/metrics") { _, _ in
            let snapshot = try await boundedSnapshot(reader: reader, timeout: timeout)
            return try makeJSONResponse(ContainerMetricsSnapshot(
                items: snapshot.items,
                observedAt: snapshot.observedAt,
                host: hostCapacity
            ))
        }
    }

    private static func boundedSnapshot<Reader: ContainerMetricsReading>(
        reader: Reader,
        timeout: Duration
    ) async throws -> ContainerMetricsSnapshot {
        let snapshots = AsyncThrowingStream<ContainerMetricsSnapshot, Error> { continuation in
            let readTask = Task {
                do {
                    continuation.yield(try await reader.containerMetrics())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                    continuation.finish(throwing: CommandExecutionError.timedOut)
                } catch {}
            }
            continuation.onTermination = { _ in
                readTask.cancel()
                timeoutTask.cancel()
            }
        }

        for try await snapshot in snapshots {
            return snapshot
        }
        throw CommandExecutionError.streamFailed
    }
}
