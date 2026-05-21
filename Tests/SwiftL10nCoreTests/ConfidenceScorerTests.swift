import XCTest
@testable import SwiftL10nCore

final class ConfidenceScorerTests: XCTestCase {

    private let scorer = ConfidenceScorer()
    private let textBase = 0.98   // TextViewRule base
    private let buttonBase = 0.95

    // MARK: - Baseline

    func testNormalStringPreservesBaseConfidence() {
        let score = scorer.score(value: "Settings", baseConfidence: textBase, enclosingContext: .empty)
        // "Settings" — single word, uppercase start, no penalties
        XCTAssertGreaterThan(score, 0.95)
    }

    func testMultiWordStringGetsBoost() {
        let single = scorer.score(value: "Settings", baseConfidence: textBase, enclosingContext: .empty)
        let multi  = scorer.score(value: "Delete Account", baseConfidence: textBase, enclosingContext: .empty)
        XCTAssertGreaterThan(multi, single)
    }

    // MARK: - Length penalties

    func testSingleCharStringPenalised() {
        let score = scorer.score(value: "A", baseConfidence: textBase, enclosingContext: .empty)
        XCTAssertLessThan(score, textBase)
    }

    func testTwoCharStringPenalised() {
        let score = scorer.score(value: "OK", baseConfidence: textBase, enclosingContext: .empty)
        // Should be penalised but still relatively high
        XCTAssertLessThan(score, textBase)
        XCTAssertGreaterThan(score, 0.80)
    }

    func testVeryLongStringPenalised() {
        let longString = String(repeating: "x ", count: 110)
        let score = scorer.score(value: longString, baseConfidence: textBase, enclosingContext: .empty)
        XCTAssertLessThan(score, textBase)
    }

    // MARK: - Content bonuses

    func testTitleCaseGetsSmallBoost() {
        let mixed    = scorer.score(value: "delete account", baseConfidence: textBase, enclosingContext: .empty)
        let title    = scorer.score(value: "Delete Account", baseConfidence: textBase, enclosingContext: .empty)
        XCTAssertGreaterThanOrEqual(title, mixed)
    }

    func testNumericContentPenalised() {
        let alpha   = scorer.score(value: "Next Step", baseConfidence: textBase, enclosingContext: .empty)
        let numeric = scorer.score(value: "Step 1 of 3", baseConfidence: textBase, enclosingContext: .empty)
        XCTAssertGreaterThan(alpha, numeric)
    }

    // MARK: - Enclosing context boosts

    func testViewSuffixTypeGivesBoost() {
        let noCtx   = scorer.score(value: "Title", baseConfidence: textBase, enclosingContext: .empty)
        let viewCtx = scorer.score(value: "Title", baseConfidence: textBase,
                                   enclosingContext: EnclosingContext(typeName: "SettingsView"))
        XCTAssertGreaterThan(viewCtx, noCtx)
    }

    func testBodyPropertyGivesBoost() {
        let noCtx   = scorer.score(value: "Title", baseConfidence: textBase, enclosingContext: .empty)
        let bodyCtx = scorer.score(value: "Title", baseConfidence: textBase,
                                   enclosingContext: EnclosingContext(propertyName: "body"))
        XCTAssertGreaterThan(bodyCtx, noCtx)
    }

    // MARK: - Clamping

    func testScoreNeverExceedsOne() {
        let ctx = EnclosingContext(typeName: "HomeView", propertyName: "body")
        let score = scorer.score(value: "Welcome to the App!", baseConfidence: 0.99, enclosingContext: ctx)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func testScoreNeverDropsBelowZero() {
        // Pathological input: empty string passes through (shouldn't happen after FPF, but guard anyway)
        let score = scorer.score(value: "", baseConfidence: 0.10, enclosingContext: .empty)
        XCTAssertGreaterThanOrEqual(score, 0.0)
    }
}
