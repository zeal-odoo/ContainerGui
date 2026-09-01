import Foundation

struct UpdateSummary: Codable, Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let updateAvailable: Bool
    let releaseURL: URL
    let publishedAt: Date?
}

protocol UpdateChecking: Sendable {
    func checkForUpdates() async throws -> UpdateSummary
}
