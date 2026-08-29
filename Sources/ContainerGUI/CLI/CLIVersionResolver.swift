import Foundation

struct CLIVersionResolver {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func resolve(explicitPath: String?) throws -> URL {
        if let explicitPath {
            return try validate(path: explicitPath)
        }

        var candidates = ["/usr/local/bin/container", "/opt/homebrew/bin/container"]
        candidates += (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/container" }

        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return try validate(path: candidate)
        }
        throw CLIResolutionError.notFound
    }

    private func validate(path: String) throws -> URL {
        guard fileManager.fileExists(atPath: path) else {
            throw CLIResolutionError.notFound
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            throw CLIResolutionError.notExecutable(path: path)
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func classify(versionText: String) -> CLIVersionClassification {
        let pattern = #"(?<![0-9])([0-9]+)\.([0-9]+)\.([0-9]+)(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: versionText,
                  range: NSRange(versionText.startIndex..., in: versionText)
              ),
              match.numberOfRanges == 4,
              let majorRange = Range(match.range(at: 1), in: versionText),
              let minorRange = Range(match.range(at: 2), in: versionText),
              let patchRange = Range(match.range(at: 3), in: versionText),
              let major = Int(versionText[majorRange]),
              let minor = Int(versionText[minorRange]),
              let patch = Int(versionText[patchRange]) else {
            return CLIVersionClassification(semanticVersion: nil, compatibility: .unrecognized)
        }

        let version = SemanticVersion(major: major, minor: minor, patch: patch)
        return CLIVersionClassification(
            semanticVersion: version,
            compatibility: major == 1 && minor == 3 ? .supported : .unsupported
        )
    }
}
