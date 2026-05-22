import XCTest
@testable import SwiftL10nCore

final class ExistingLocalizationDetectorTests: XCTestCase {

    // MARK: - Helpers

    private func detect(
        source: String,
        patterns: [String] = [],
        excludeArgumentsOf: [String] = []
    ) -> ExistingLocalizationDetector.Result {
        let config = ExistingLocalizationDetector.Config(
            patterns: patterns,
            excludeArgumentsOf: excludeArgumentsOf
        )
        return ExistingLocalizationDetector(config: config).detect(source: source, filePath: "Test.swift")
    }

    // MARK: - dotPath reconstruction

    func testDotPathReconstructsSimpleMemberAccess() {
        let source = "let x = L10n.save"
        let result = detect(source: source, patterns: ["L10n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].fullExpression, "L10n.save")
        XCTAssertEqual(result.detections[0].matchedPattern, "L10n")
        XCTAssertEqual(result.detections[0].kind, .memberAccess)
    }

    func testDotPathReconstructsThreeLevelChain() {
        let source = "let x = i18n.Settings.title"
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].fullExpression, "i18n.Settings.title")
        XCTAssertEqual(result.detections[0].matchedPattern, "i18n")
    }

    func testDotPathReconstructsCallExpression() {
        let source = "let x = i18n.Settings.title()"
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].fullExpression, "i18n.Settings.title")
        XCTAssertEqual(result.detections[0].kind, .callExpression)
    }

    // MARK: - Pattern matching

    func testPatternWithTrailingDot() {
        let source = "Text(L10n.save)"
        let result = detect(source: source, patterns: ["L10n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].matchedPattern, "L10n")
    }

    func testPatternWithoutTrailingDot() {
        let source = "Text(L10n.save)"
        let result = detect(source: source, patterns: ["L10n"])
        XCTAssertEqual(result.detections.count, 1)
    }

    func testPatternBoundaryDoesNotMatchPrefix() {
        // "L10n" must NOT match "L10nHelper.save"
        let source = "let x = L10nHelper.save"
        let result = detect(source: source, patterns: ["L10n."])
        XCTAssertEqual(result.detections.count, 0, "L10nHelper must not match pattern 'L10n.'")
    }

    func testMultiplePatterns() {
        let source = """
        let a = L10n.save
        let b = i18n.Common.cancel()
        let c = Strings.title
        """
        let result = detect(source: source, patterns: ["L10n.", "i18n.", "Strings."])
        XCTAssertEqual(result.detections.count, 3)
        let patterns = Set(result.detections.map(\.matchedPattern))
        XCTAssertEqual(patterns, ["L10n", "i18n", "Strings"])
    }

    // MARK: - Call expression vs member access

    func testCallExpressionKind() {
        let source = "i18n.Common.save()"
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].kind, .callExpression)
    }

    func testMemberAccessKind() {
        let source = "let x = L10n.cancel"
        let result = detect(source: source, patterns: ["L10n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].kind, .memberAccess)
    }

    func testCallExpressionNotDoubleReported() {
        // i18n.Settings.title() should produce exactly one detection (call),
        // not also a memberAccess for i18n.Settings.title
        let source = "i18n.Settings.title()"
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 1)
        XCTAssertEqual(result.detections[0].kind, .callExpression)
    }

    func testSubexpressionNotDoubleReported() {
        // i18n.Settings in i18n.Settings.title should NOT be separately reported
        let source = "let x = i18n.Settings.title"
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 1, "Only the outermost member access should be detected")
        XCTAssertEqual(result.detections[0].fullExpression, "i18n.Settings.title")
    }

    // MARK: - No patterns → empty result

    func testEmptyConfigReturnsEmpty() {
        let source = "let x = L10n.save"
        let result = detect(source: source, patterns: [], excludeArgumentsOf: [])
        XCTAssertTrue(result.detections.isEmpty)
        XCTAssertTrue(result.suppressionLocations.isEmpty)
    }

    // MARK: - Excluded function arguments → suppression locations

    func testExcludedFunctionArgumentAddedToSuppressionIndex() {
        // NSLocalizedString("Save", comment: "") has two string literal args: "Save" and ""
        let source = #"let x = NSLocalizedString("Save", comment: "")"#
        let result = detect(source: source, excludeArgumentsOf: ["NSLocalizedString"])
        XCTAssertTrue(result.detections.isEmpty, "NSLocalizedString is not a pattern detection")
        XCTAssertEqual(result.suppressionLocations.count, 2, "Both string literal arguments are suppressed")
    }

    func testExcludedFunctionWithMultipleStringArguments() {
        // Both string literals should be recorded as suppressed
        let source = #"NSLocalizedString("Save", comment: "Save button")"#
        let result = detect(source: source, excludeArgumentsOf: ["NSLocalizedString"])
        XCTAssertEqual(result.suppressionLocations.count, 2)
    }

    func testNonExcludedFunctionNotSuppressed() {
        let source = #"let x = SomeHelper("Save")"#
        let result = detect(source: source, excludeArgumentsOf: ["NSLocalizedString"])
        XCTAssertTrue(result.suppressionLocations.isEmpty)
    }

    func testStringLocalizedExcluded() {
        let source = #"let s = String(localized: "Save")"#
        let result = detect(source: source, excludeArgumentsOf: ["String"])
        // "Save" is a labeled arg — ExistingLocalizationDetector records all string literals
        XCTAssertGreaterThanOrEqual(result.suppressionLocations.count, 1)
    }

    // MARK: - Real-world fixtures

    func testSwiftGenCoexistenceFixture() {
        let source = """
        import SwiftUI

        struct SettingsView: View {
            var body: some View {
                VStack {
                    Text(L10n.Settings.title)
                    Button(action: {}) {
                        Text(L10n.Settings.saveButton)
                    }
                    Text("Hardcoded string")
                }
                .navigationTitle(L10n.Settings.navTitle())
            }
        }
        """
        let result = detect(source: source, patterns: ["L10n."])
        // L10n.Settings.title, L10n.Settings.saveButton, L10n.Settings.navTitle()
        XCTAssertGreaterThanOrEqual(result.detections.count, 3)
        XCTAssertTrue(result.detections.allSatisfy { $0.matchedPattern == "L10n" })
    }

    func testMixedExistingAndHardcoded() {
        let source = """
        import SwiftUI

        struct OnboardingView: View {
            var body: some View {
                VStack {
                    Text(i18n.Onboarding.title())
                    Text("Get Started")
                    Button(i18n.Onboarding.continueButton()) {}
                    Text("Skip for now")
                }
            }
        }
        """
        let result = detect(source: source, patterns: ["i18n."])
        XCTAssertEqual(result.detections.count, 2)
        let expressions = result.detections.map(\.fullExpression).sorted()
        XCTAssertEqual(expressions, ["i18n.Onboarding.continueButton", "i18n.Onboarding.title"])
    }

    func testNSLocalizedStringMixedInFile() {
        let source = """
        import Foundation

        class SettingsViewModel {
            let title = NSLocalizedString("Settings", comment: "Nav title")
            let subtitle = NSLocalizedString("Manage your preferences", comment: "")
            let version = "1.0.0"
        }
        """
        let result = detect(source: source, excludeArgumentsOf: ["NSLocalizedString"])
        XCTAssertTrue(result.detections.isEmpty)
        XCTAssertEqual(result.suppressionLocations.count, 4, "4 string args across 2 NSLocalizedString calls")
    }

    // MARK: - Location accuracy

    func testDetectionLocationIsRecorded() {
        let source = """
        import SwiftUI
        let x = L10n.save
        """
        let result = detect(source: source, patterns: ["L10n."])
        XCTAssertEqual(result.detections.count, 1)
        let loc = result.detections[0].location
        XCTAssertEqual(loc.file, "Test.swift")
        XCTAssertEqual(loc.line, 2)
    }
}
