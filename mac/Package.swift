// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lensfix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Lensfix",
            path: "Sources/Lensfix",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
