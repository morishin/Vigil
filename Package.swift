// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vigil",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vigil",
            path: "Sources/Vigil",
            resources: [.copy("Resources/candle.svg")]
        )
    ]
)
