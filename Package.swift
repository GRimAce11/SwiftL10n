// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftL10n",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "swiftl10n", targets: ["swiftl10n"]),
        .library(name: "SwiftL10nCore", targets: ["SwiftL10nCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // MARK: - CLI Executable
        .executableTarget(
            name: "swiftl10n",
            dependencies: [
                "SwiftL10nCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/swiftl10n"
        ),

        // MARK: - Core Library (independently testable, no CLI dependency)
        .target(
            name: "SwiftL10nCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/SwiftL10nCore"
        ),

        // MARK: - Test Target
        .testTarget(
            name: "SwiftL10nCoreTests",
            dependencies: [
                "SwiftL10nCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Tests/SwiftL10nCoreTests"
        ),
    ]
)
