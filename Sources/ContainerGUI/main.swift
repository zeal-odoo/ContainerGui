import Darwin
import Foundation
import Logging

if CommandLine.arguments.dropFirst().first == "--ai-log-worker" {
    guard CommandLine.arguments.count == 3 else { exit(2) }
    exit(AILogWorker.run(modelDirectory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)))
}

let configuration = try AppConfiguration()
let logger = Logger(label: "ContainerGUI")
logger.info("Container GUI starting", metadata: [
    "host": "\(configuration.host)",
    "port": "\(configuration.port)",
])
try await AppFactory.makeApplication(configuration: configuration).runService()
