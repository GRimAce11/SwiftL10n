import XCTest
@testable import SwiftL10nCore

/// Integration-level tests: scan complete realistic fixtures and verify detection quality.
/// These test the PIPELINE (scanner + filter + scorer) together, not individual components.
final class FixtureTests: XCTestCase {

    private let scanner = StringScanner()

    // MARK: - Settings view

    func testSettingsViewDetectionCount() {
        let result = scanner.scan(source: TestFixtures.settingsView, filePath: "SettingsView.swift")
        // Expected: Profile, Security, Delete Account, Push Notifications, Reset Preferences,
        //           Settings (navTitle), Are you sure? (alert), Delete (button), Cancel (button)
        XCTAssertGreaterThanOrEqual(result.detectedStrings.count, 9)
    }

    func testSettingsViewNoFalsePositives() {
        let result = scanner.scan(source: TestFixtures.settingsView, filePath: "SettingsView.swift")
        let values = result.detectedStrings.map(\.value)
        // SF Symbol names must NOT appear
        XCTAssertFalse(values.contains("person.circle"))
        XCTAssertFalse(values.contains("lock.shield"))
        XCTAssertFalse(values.contains("gear"))
    }

    func testSettingsViewContextExtraction() {
        let result = scanner.scan(source: TestFixtures.settingsView, filePath: "SettingsView.swift")
        // All strings should be inside SettingsView
        let types = Set(result.detectedStrings.compactMap(\.enclosingContext.typeName))
        XCTAssertTrue(types.contains("SettingsView"))
    }

    func testSettingsViewAllConfidenceAboveThreshold() {
        let result = scanner.scan(source: TestFixtures.settingsView, filePath: "SettingsView.swift")
        for s in result.detectedStrings {
            XCTAssertGreaterThan(s.confidence, 0.85,
                "Low confidence for \"\(s.value)\": \(s.confidence)")
        }
    }

    // MARK: - False-positive noise file

    func testFalsePositiveFileProducesZeroDetections() {
        let result = scanner.scan(source: TestFixtures.falsePositiveNoise, filePath: "AnalyticsManager.swift")
        XCTAssertEqual(
            result.detectedStrings.count, 0,
            "Unexpected detections: \(result.detectedStrings.map(\.value))"
        )
    }

    // MARK: - All call sites

    func testAllCallSitesAreDetected() {
        let result = scanner.scan(source: TestFixtures.allCallSites, filePath: "AllCallSitesView.swift")
        let contexts = Set(result.detectedStrings.map(\.context))
        XCTAssertTrue(contexts.contains(.textView))
        XCTAssertTrue(contexts.contains(.buttonLabel))
        XCTAssertTrue(contexts.contains(.labelView))
        XCTAssertTrue(contexts.contains(.toggle))
        XCTAssertTrue(contexts.contains(.textField))
        XCTAssertTrue(contexts.contains(.accessibilityLabel))
        XCTAssertTrue(contexts.contains(.navigationTitle))
        XCTAssertTrue(contexts.contains(.alert))
        XCTAssertTrue(contexts.contains(.confirmationDialog))
    }

    func testAllCallSitesSFSymbolsAreExcluded() {
        let result = scanner.scan(source: TestFixtures.allCallSites, filePath: "AllCallSitesView.swift")
        let values = result.detectedStrings.map(\.value)
        XCTAssertFalse(values.contains("gear"), "SF Symbol 'gear' should be excluded")
    }

    // MARK: - Text(verbatim:) opt-out

    func testVerbatimIsNotDetected() {
        let result = scanner.scan(source: TestFixtures.verbatimOptOut, filePath: "VerbatimView.swift")
        let values = result.detectedStrings.map(\.value)
        XCTAssertFalse(values.contains("raw content that should NOT be localised"))
        XCTAssertTrue(values.contains("But this one SHOULD be localised"))
        XCTAssertEqual(result.detectedStrings.count, 1)
    }

    // MARK: - Namespace inference on fixture

    func testSettingsViewMapsToCorrectNamespace() {
        let result = scanner.scan(source: TestFixtures.settingsView, filePath: "/App/SettingsView.swift")
        let namespace = NamespaceInferrer().infer(from: [
            ("/App/SettingsView.swift", result.detectedStrings)
        ])
        XCTAssertEqual(namespace.first?.name, "Settings")
    }
}
