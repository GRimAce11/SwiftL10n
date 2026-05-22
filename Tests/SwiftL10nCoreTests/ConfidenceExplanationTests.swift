import XCTest
@testable import SwiftL10nCore

final class ConfidenceExplanationTests: XCTestCase {

    private let scorer = ConfidenceScorer()

    // MARK: - ScoreExplanation structure

    func testExplanationBaseMirrorsFunctionBase() {
        let expl = scorer.explain(value: "Save", baseConfidence: 0.98, enclosingContext: .empty)
        XCTAssertEqual(expl.base, 0.98, accuracy: 0.001)
    }

    func testExplanationFinalMatchesScoreOutput() {
        let value = "Delete Account"
        let base  = 0.95
        let ctx   = EnclosingContext.empty
        let score = scorer.score(value: value, baseConfidence: base, enclosingContext: ctx)
        let expl  = scorer.explain(value: value, baseConfidence: base, enclosingContext: ctx)
        XCTAssertEqual(score, expl.final, accuracy: 0.0001)
    }

    func testShortStringGetsNegativeFactor() {
        let expl = scorer.explain(value: "OK", baseConfidence: 0.98, enclosingContext: .empty)
        let shortFactor = expl.factors.first { $0.delta < 0 && $0.reason.contains("short") }
        XCTAssertNotNil(shortFactor, "Very short string (2 chars) must produce a negative factor")
        XCTAssertLessThan(shortFactor!.delta, 0)
    }

    func testMultiWordPhrasGetsPositiveFactor() {
        let expl = scorer.explain(value: "Delete Account", baseConfidence: 0.95, enclosingContext: .empty)
        let multiWord = expl.factors.first { $0.reason.contains("multi-word") }
        XCTAssertNotNil(multiWord, "Multi-word phrase must produce a positive factor")
        XCTAssertGreaterThan(multiWord!.delta, 0)
    }

    func testViewContextGetsPositiveFactor() {
        let ctx = EnclosingContext(typeName: "SettingsView", propertyName: "body", functionName: nil)
        let expl = scorer.explain(value: "Settings", baseConfidence: 0.95, enclosingContext: ctx)
        let viewFactor = expl.factors.first { $0.reason.contains("View") || $0.reason.contains("body") }
        XCTAssertNotNil(viewFactor, "View-family type name and body property must each produce a factor")
    }

    func testSummaryIsNonEmptyWhenFactorsExist() {
        let expl = scorer.explain(value: "Delete Account", baseConfidence: 0.95, enclosingContext: .empty)
        if !expl.factors.isEmpty {
            XCTAssertFalse(expl.summary.isEmpty)
        }
    }

    func testEmptyStringGetsLargeNegativeFactor() {
        let expl = scorer.explain(value: "", baseConfidence: 0.98, enclosingContext: .empty)
        let emptyFactor = expl.factors.first { $0.reason.contains("empty") }
        XCTAssertNotNil(emptyFactor)
        XCTAssertEqual(emptyFactor!.delta, -0.30, accuracy: 0.001)
    }

    func testFinalIsClampedToZeroOne() {
        // Extreme base + large negative deltas
        let expl = scorer.explain(value: "", baseConfidence: 0.1, enclosingContext: .empty)
        XCTAssertGreaterThanOrEqual(expl.final, 0.0)
        XCTAssertLessThanOrEqual(expl.final, 1.0)

        // Extreme base + large positive deltas
        let expl2 = scorer.explain(value: "Welcome to the App", baseConfidence: 0.99, enclosingContext: .empty)
        XCTAssertGreaterThanOrEqual(expl2.final, 0.0)
        XCTAssertLessThanOrEqual(expl2.final, 1.0)
    }

    // MARK: - DetectedString integration

    func testDetectedStringCarriesExplanation() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Delete Account") }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")

        let detected = result.detectedStrings.first
        XCTAssertNotNil(detected, "Must detect a string")
        XCTAssertNotNil(detected?.scoreExplanation, "scoreExplanation must be populated by scanner")
        XCTAssertFalse(detected?.scoreExplanation?.factors.isEmpty ?? true, "Explanation must have factors")
    }

    // MARK: - suggestedPropertyName

    func testSuggestedPropertyNameForTextView() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Welcome Back") }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")
        let s       = result.detectedStrings.first
        XCTAssertEqual(s?.suggestedPropertyName, "welcomeBack")
    }

    func testSuggestedPropertyNameForButton() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Button("Delete Account") {} }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")
        let s       = result.detectedStrings.first
        XCTAssertEqual(s?.suggestedPropertyName, "deleteAccountButtonTitle")
    }

    func testSuggestedPropertyNameForNavigationTitle() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("x").navigationTitle("Settings") }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")
        let navString = result.detectedStrings.first { $0.context == .navigationTitle }
        XCTAssertEqual(navString?.suggestedPropertyName, "settingsNavigationTitle")
    }

    func testSuggestedPropertyNameForEmptyValueFallback() {
        let ds = DetectedString(value: "", location: .init(file: "f", line: 1, column: 1), context: .textView)
        XCTAssertEqual(ds.suggestedPropertyName, "localizedString")
    }

    // MARK: - Codable round-trip

    func testScoreExplanationCodableRoundTrip() throws {
        let original = ScoreExplanation(
            base: 0.95,
            factors: [
                .init(reason: "multi-word phrase", delta: 0.02),
                .init(reason: "short (3 chars)", delta: -0.04)
            ],
            final: 0.93
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoreExplanation.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
