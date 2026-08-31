import Foundation
import Hummingbird
import HTTPTypes

enum APIAuthenticationError: Error {
    case invalidCredentialFile
    case unableToCreateCredentialFile
}

struct APIAuthentication: Sendable {
    static let username = "container-gui"

    let token: String

    var authorizationHeaderValue: String {
        let credential = Data("\(Self.username):\(token)".utf8).base64EncodedString()
        return "Basic \(credential)"
    }

    static var defaultTokenFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ContainerGUI", isDirectory: true)
            .appendingPathComponent("auth-token")
    }

    static func loadOrCreate(
        tokenFileURL: URL = defaultTokenFileURL
    ) throws -> APIAuthentication {
        let fileManager = FileManager.default
        let directoryURL = tokenFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        let directoryValues = try directoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard directoryValues.isDirectory == true,
              directoryValues.isSymbolicLink != true else {
            throw APIAuthenticationError.invalidCredentialFile
        }

        if fileManager.fileExists(atPath: tokenFileURL.path) {
            let values = try tokenFileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw APIAuthenticationError.invalidCredentialFile
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenFileURL.path
            )
            let token = try String(contentsOf: tokenFileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValid(token) else {
                throw APIAuthenticationError.invalidCredentialFile
            }
            return APIAuthentication(token: token)
        }

        let token = randomToken()
        do {
            try Data(token.utf8).write(to: tokenFileURL, options: .withoutOverwriting)
        } catch {
            throw APIAuthenticationError.unableToCreateCredentialFile
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenFileURL.path
        )
        return APIAuthentication(token: token)
    }

    private static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in
            String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
        }.joined()
    }

    private static func isValid(_ token: String) -> Bool {
        token.utf8.count == 64 && token.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102: true
            default: false
            }
        }
    }
}

struct APIAuthenticationMiddleware<Context: RequestContext>: RouterMiddleware {
    let authentication: APIAuthentication

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard Self.constantTimeEqual(
            request.headers[.authorization] ?? "",
            authentication.authorizationHeaderValue
        ) else {
            var response = makeProblemResponse(ProblemDetail(code: .authenticationRequired))
            response.headers[HTTPField.Name("WWW-Authenticate")!] =
                #"Basic realm="Container GUI", charset="UTF-8""#
            return addSecurityHeaders(to: response)
        }
        return try await next(request, context)
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = left.count ^ right.count
        let maximumCount = max(left.count, right.count)
        for index in 0..<maximumCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }
        return difference == 0
    }
}
