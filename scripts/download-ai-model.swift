import Foundation

// Development-only fixed model verification. Build together with AIModelCatalog.swift
// and AIModelStore.swift; run from the repository with CONTAINER_GUI_AI_DOWNLOAD_TEST=1.
@main
struct DownloadAIModelForValidation {
    static func main() async throws {
        guard ProcessInfo.processInfo.environment["CONTAINER_GUI_AI_DOWNLOAD_TEST"] == "1" else {
            throw AIModelStoreError.downloadFailed
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/ai-model-test")
        let store = AIModelStore(directory: directory)
        let progress = Task {
            while !Task.isCancelled {
                let state = await store.status()
                print("AI_MODEL_DOWNLOAD_BYTES=\(state.downloadedBytes)/\(state.totalBytes)")
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        defer { progress.cancel() }
        try await store.install()
        print("AI_MODEL_VERIFIED_DIRECTORY=\(try await store.verifiedDirectory().path)")
    }
}
