import Logging

let configuration = try AppConfiguration()
let authentication = try APIAuthentication.loadOrCreate()
let logger = Logger(label: "ContainerGUI")
logger.info("Container GUI starting", metadata: [
    "host": "\(configuration.host)",
    "port": "\(configuration.port)",
    "authenticationUsername": "\(APIAuthentication.username)",
    "authenticationTokenFile": "\(APIAuthentication.defaultTokenFileURL.path)",
])
try await AppFactory.makeApplication(
    configuration: configuration,
    authentication: authentication
).runService()
