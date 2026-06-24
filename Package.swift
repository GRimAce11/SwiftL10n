// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftL10n",
    platforms: [
        .macOS(.v13),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        // ── For app targets (Xcode or SwiftPM) ──────────────────────────────
        // Add SwiftL10nPlugin to your app target — it runs `swiftl10n scan`
        // before every compile so Generated/ is always up to date.
        .plugin(name: "SwiftL10nPlugin", targets: ["SwiftL10nPlugin"]),

        // ── For programmatic / library use ──────────────────────────────────
        // Import SwiftL10nCore if you need the scanning API directly.
        .library(name: "SwiftL10nCore", targets: ["SwiftL10nCore"]),

        // ── For terminal use only ────────────────────────────────────────────
        // swiftl10n is a CLI tool — do NOT add it to an app target.
        // Install it once: swift build -c release && cp .build/release/swiftl10n /usr/local/bin/
        // Then run: swiftl10n scan Sources/ --output Sources/Generated/Strings.swift
        .executable(name: "swiftl10n", targets: ["swiftl10n"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        // MARK: - Build Tool Plugin
        .plugin(
            name: "SwiftL10nPlugin",
            capability: .buildTool(),
            dependencies: [.target(name: "swiftl10n")]
        ),

        // MARK: - CLI Executable
        .executableTarget(
            name: "swiftl10n",
            dependencies: [
                "SwiftL10nCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
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
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/SwiftL10nCoreTests"
        ),
    ]
)
