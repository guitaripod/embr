// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmbrCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EmbrCore", targets: ["EmbrCore"])
    ],
    targets: [
        .target(
            name: "EmbrCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "EmbrCoreTests",
            dependencies: ["EmbrCore"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
