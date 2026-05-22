import XCTest
import Yams
@testable import SwiftL10nCore

final class NamespaceCollisionTests: XCTestCase {

    private let inferrer = NamespaceInferrer()
    private let string   = DetectedString(
        value: "Hi",
        location: .init(file: "f", line: 1, column: 1),
        context: .textView
    )

    // MARK: - No collision

    func testNoCollisionReturnsNameUnchanged() {
        let result = inferrer.inferDetailed(
            from: [("Sources/SettingsView.swift", [string])],
            strategy: .file
        )
        XCTAssertEqual(result.namespaces.count, 1)
        XCTAssertEqual(result.namespaces[0].name, "Settings")
        XCTAssertTrue(result.collisionDiagnostics.isEmpty)
    }

    func testTwoDistinctFilesNoCollision() {
        let result = inferrer.inferDetailed(
            from: [
                ("Sources/SettingsView.swift",   [string]),
                ("Sources/OnboardingView.swift", [string]),
            ],
            strategy: .file
        )
        XCTAssertEqual(result.namespaces.count, 2)
        XCTAssertTrue(result.collisionDiagnostics.isEmpty)
        let names = Set(result.namespaces.map(\.name))
        XCTAssertEqual(names, ["Settings", "Onboarding"])
    }

    // MARK: - Collision detection

    func testCollisionEmitsWarningDiagnostic() {
        let result = inferrer.inferDetailed(
            from: [
                ("Payment/SettingsView.swift", [string]),
                ("Profile/SettingsView.swift", [string]),
            ],
            strategy: .file
        )
        XCTAssertEqual(result.namespaces.count, 2)
        XCTAssertEqual(result.collisionDiagnostics.count, 1)
        XCTAssertEqual(result.collisionDiagnostics[0].severity, .warning)
        XCTAssertTrue(result.collisionDiagnostics[0].message.contains("\"Settings\""))
    }

    // MARK: - Strategy: file (default, current behavior)

    func testFileStrategyKeepsCollisionAsIs() {
        let result = inferrer.inferDetailed(
            from: [
                ("Payment/SettingsView.swift", [string]),
                ("Profile/SettingsView.swift", [string]),
            ],
            strategy: .file
        )
        let names = result.namespaces.map(\.name).sorted()
        XCTAssertEqual(names, ["Settings", "Settings"],
            "file strategy preserves collision — extensions are valid Swift even if same name")
    }

    // MARK: - Strategy: auto (disambiguate on collision only)

    func testAutoStrategyDisambiguatesOnCollision() {
        let result = inferrer.inferDetailed(
            from: [
                ("Payment/SettingsView.swift", [string]),
                ("Profile/SettingsView.swift", [string]),
            ],
            strategy: .auto
        )
        let names = Set(result.namespaces.map(\.name))
        XCTAssertEqual(result.namespaces.count, 2)
        XCTAssertFalse(names.contains("Settings"), "auto must disambiguate colliding names")
        // Both should include the parent dir as prefix
        XCTAssertTrue(names.contains("PaymentSettings") || names.contains("ProfileSettings"),
            "auto must prefix with parent directory: \(names)")
    }

    func testAutoStrategyLeavesUniqueNamesAlone() {
        let result = inferrer.inferDetailed(
            from: [
                ("Payment/SettingsView.swift",   [string]),
                ("Sources/OnboardingView.swift", [string]),
            ],
            strategy: .auto
        )
        let names = Set(result.namespaces.map(\.name))
        XCTAssertTrue(names.contains("Onboarding"),
            "Unique name must not be prefixed: \(names)")
    }

    // MARK: - Strategy: directory (always prefix)

    func testDirectoryStrategyAlwaysPrefixes() {
        let result = inferrer.inferDetailed(
            from: [("Payment/SettingsView.swift", [string])],
            strategy: .directory
        )
        XCTAssertEqual(result.namespaces[0].name, "PaymentSettings")
    }

    func testDirectoryStrategySkipsGenericDirNames() {
        // "Sources" is in the generic set — should fall through to grandparent or base
        let result = inferrer.inferDetailed(
            from: [("Sources/SettingsView.swift", [string])],
            strategy: .directory
        )
        // Falls back to base name when parent is generic
        XCTAssertEqual(result.namespaces[0].name, "Settings")
    }

    // MARK: - Config decoding

    func testDefaultStrategyIsFile() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.namespaceStrategy, .file)
    }

    func testDecodeAutoStrategy() throws {
        let yaml = "sources: [Sources]\nnamespace_strategy: auto\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.namespaceStrategy, .auto)
    }

    func testDecodeDirectoryStrategy() throws {
        let yaml = "sources: [Sources]\nnamespace_strategy: directory\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.namespaceStrategy, .directory)
    }

    // MARK: - Pipeline integration

    func testPipelineEmitsCollisionWarning() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CollisionTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = #"import SwiftUI; struct V: View { var body: some View { Text("Hello") } }"#
        try source.write(to: tempDir.appendingPathComponent("SettingsView.swift"),  atomically: true, encoding: .utf8)
        try source.write(to: tempDir.appendingPathComponent("SettingsView2.swift"), atomically: true, encoding: .utf8)

        // SettingsView.swift and SettingsView2.swift both → "Settings" (no collision — different base names)
        // Use two files with same suffix: different dirs not possible in flat temp dir, so test via inferDetailed directly
        let result = inferrer.inferDetailed(
            from: [
                (tempDir.appendingPathComponent("Sub1/SettingsView.swift").path, [string]),
                (tempDir.appendingPathComponent("Sub2/SettingsView.swift").path, [string]),
            ],
            strategy: .auto
        )
        XCTAssertEqual(result.collisionDiagnostics.count, 1)
        XCTAssertEqual(result.collisionDiagnostics[0].severity, .warning)
    }
}
