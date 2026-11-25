// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmbrCLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "embr", targets: ["embr"])
    ],
    dependencies: [
        .package(path: "../Core/EmbrCore"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.9.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0")
    ],
    targets: [
        .target(
            name: "EmbrCLIKit",
            dependencies: [
                .product(name: "EmbrCore", package: "EmbrCore"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "embr",
            dependencies: ["EmbrCLIKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "EmbrCLITests",
            dependencies: ["EmbrCLIKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
