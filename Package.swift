// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FCleaner",
            path: "Sources/FCleaner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FCleanerTests",
            dependencies: ["FCleaner"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
