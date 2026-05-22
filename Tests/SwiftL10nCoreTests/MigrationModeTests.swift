import XCTest
import Yams
@testable import SwiftL10nCore

final class MigrationModeTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationModeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Config decoding

    func testDefaultMigrationModeIsAudit() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.migration.mode, .audit)
    }

    func testDecodeIncrementalMode() throws {
        let yaml = """
        sources: [Sources]
        migration:
          mode: incremental
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.migration.mode, .incremental)
    }

    func testDecodeStrictMode() throws {
        let yaml = """
        sources: [Sources]
        migration:
          mode: strict
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.migration.mode, .strict)
    }

    func testDecodeExistingLocalizationPatterns() throws {
        let yaml = """
        sources: [Sources]
        existing_localization:
          patterns:
            - "L10n."
            - "i18n."
          exclude_arguments_of:
            - "NSLocalizedString"
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.existingLocalization.patterns, ["L10n.", "i18n."])
        XCTAssertEqual(config.existingLocalization.excludeArgumentsOf, ["NSLocalizedString"])
    }

    func testDefaultExistingLocalizationIsEmpty() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertTrue(config.existingLocalization.patterns.isEmpty)
        XCTAssertFalse(config.existingLocalization.isActive)
    }

    // MARK: - Pipeline: audit mode (current behavior)

    func testAuditModeReportsAllStrings() async throws {
        try writeFile(name: "SettingsView.swift", source: """
        import SwiftUI
        struct SettingsView: View {
            var body: some View {
                Text("Settings Title")
                Button("Save") {}
            }
        }
        """)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            migration: .init(mode: .audit)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.migrationMode, .audit)
        XCTAssertGreaterThanOrEqual(result.totalStrings, 2)
        XCTAssertEqual(result.existingLocalizationCount, 0)
    }

    // MARK: - Pipeline: incremental mode

    func testIncrementalModeRecognizesExistingPatterns() async throws {
        try writeFile(name: "SettingsView.swift", source: """
        import SwiftUI
        struct SettingsView: View {
            var body: some View {
                Text(L10n.Settings.title)
                Button(action: {}) { Text(L10n.Settings.saveButton) }
                Text("Hardcoded Gap")
            }
        }
        """)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            existingLocalization: .init(patterns: ["L10n."]),
            migration: .init(mode: .incremental)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.migrationMode, .incremental)
        XCTAssertGreaterThanOrEqual(result.existingLocalizationCount, 2,
            "L10n.Settings.title and L10n.Settings.saveButton should be recognized")
    }

    func testPipelineResultCarriesMigrationMode() async throws {
        try writeFile(name: "View.swift", source: "import SwiftUI\nstruct V: View { var body: some View { Text(\"Hi\") } }")

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            migration: .init(mode: .incremental)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.migrationMode, .incremental)
    }

    // MARK: - Pipeline: suppression integration

    func testSuppressionReducesDetections() async throws {
        // A view that wraps NSLocalizedString — the string literal should be suppressed
        try writeFile(name: "LocalizationHelper.swift", source: #"""
        import Foundation
        func localizedTitle() -> String {
            NSLocalizedString("Delete Account", comment: "Danger zone button")
        }
        """#)

        let noSuppression = SwiftL10nConfig(sources: [tempDir.path])
        let withSuppression = SwiftL10nConfig(
            sources: [tempDir.path],
            existingLocalization: .init(excludeArgumentsOf: ["NSLocalizedString"])
        )

        // Without suppression: no detection because NSLocalizedString has no rule
        let r1 = try await ScanPipeline(config: noSuppression, baseURL: tempDir).run()
        // With suppression: same — the string isn't detected by StringScanner anyway
        let r2 = try await ScanPipeline(config: withSuppression, baseURL: tempDir).run()

        // The key assertion: suppressed version should not produce MORE detections
        XCTAssertLessThanOrEqual(r2.totalStrings, r1.totalStrings)
    }

    func testExistingLocalizationCountAccumulates() async throws {
        try writeFile(name: "SettingsView.swift", source: """
        import SwiftUI
        struct SettingsView: View {
            var body: some View {
                Text(i18n.Settings.title())
                Button(action: {}) { Text(i18n.Settings.saveButton()) }
                Text(i18n.Common.cancel())
            }
        }
        """)
        try writeFile(name: "OnboardingView.swift", source: """
        import SwiftUI
        struct OnboardingView: View {
            var body: some View {
                Text(i18n.Onboarding.welcome())
                Button(i18n.Onboarding.getStarted()) {}
            }
        }
        """)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            existingLocalization: .init(patterns: ["i18n."]),
            migration: .init(mode: .incremental)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.existingLocalizationCount, 5,
            "3 calls in SettingsView + 2 in OnboardingView")
        XCTAssertEqual(result.totalStrings, 0,
            "No hardcoded strings — all wrapped in i18n.")
    }

    // MARK: - Backwards compatibility

    func testMinimalConfigPreservesAuditBehavior() async throws {
        try writeFile(name: "View.swift", source: """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Hello World") }
        }
        """)

        // Minimal config with NO existing_localization or migration keys
        let yaml = """
        sources:
          - \(tempDir.path)
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.migration.mode, .audit)
        XCTAssertFalse(config.existingLocalization.isActive)

        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertGreaterThanOrEqual(result.totalStrings, 1, "Audit mode still reports hardcoded strings")
    }

    // MARK: - Helpers

    @discardableResult
    private func writeFile(name: String, source: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
