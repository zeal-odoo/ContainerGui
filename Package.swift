// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ContainerGUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ContainerGUI", targets: ["ContainerGUI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.26.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "ContainerGUI",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            resources: [
                .copy("Resources/Public")
            ]
        ),
        .testTarget(
            name: "ContainerGUITests",
            dependencies: [
                "ContainerGUI",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
