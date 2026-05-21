// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftL10nDemo",
    platforms: [.macOS(.v14)],   // @Observable requires macOS 14
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SwiftL10nDemo",
            dependencies: [
                .product(name: "SwiftL10nCore", package: "SwiftL10n"),
            ],
            path: "Sources/SwiftL10nDemo"
        ),
    ]
)
