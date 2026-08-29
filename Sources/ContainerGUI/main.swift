import Logging

let configuration = try AppConfiguration()
let logger = Logger(label: "ContainerGUI")
logger.info("Container GUI starting", metadata: [
    "host": "\(configuration.host)",
    "port": "\(configuration.port)",
])
try await AppFactory.makeApplication(configuration: configuration).runService()
