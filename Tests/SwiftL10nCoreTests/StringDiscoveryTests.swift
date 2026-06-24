import XCTest
import Yams
@testable import SwiftL10nCore

// MARK: - Static string constant detection

final class StaticStringConstantTests: XCTestCase {

    // MARK: Helpers

    private func scan(_ source: String, minConfidence: Double = 0.0) -> [DetectedString] {
        let scanner = StringScanner(
            minimumConfidence: minConfidence,
            discoveryConfig: .init(staticConstants: true, indirectArgumentHints: false)
        )
        return scanner.scan(source: source, filePath: "Test.swift").detectedStrings
    }

    // MARK: Basic detection

    func testDetectsStaticLetInEnum() {
        let source = """
        enum Strings {
            static let save = "Save"
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].value, "Save")
        XCTAssertEqual(results[0].context, .staticStringConstant)
    }

    func testDetectsStaticLetInStruct() {
        let source = """
        struct Titles {
            static let welcomeBack = "Welcome Back"
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].value, "Welcome Back")
    }

    func testDetectsStaticLetInClass() {
        let source = """
        class Labels {
            static let deleteAccount = "Delete Account"
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].value, "Delete Account")
    }

    func testDetectsMultipleStaticConstants() {
        let source = """
        enum Titles {
            static let save   = "Save"
            static let cancel = "Cancel"
            static let done   = "Done"
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 3)
        let values = Set(results.map(\.value))
        XCTAssertTrue(values.contains("Save"))
        XCTAssertTrue(values.contains("Cancel"))
        XCTAssertTrue(values.contains("Done"))
    }

    // MARK: Confidence

    func testStaticConstantConfidenceIsLow() {
        let source = """
        enum S { static let title = "Settings" }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(results[0].confidence, 0.85,
            "Static constants should be below the default 0.85 threshold")
    }

    func testStaticConstantFilteredAtDefaultThreshold() {
        let source = """
        enum S { static let title = "Settings" }
        """
        // Default minimumConfidence = 0.85 — static constants (≈0.60) must not appear
        let results = scan(source, minConfidence: 0.85)
        XCTAssertEqual(results.count, 0,
            "Static constants must be invisible at the default 0.85 threshold")
    }

    func testStaticConstantSurfacedBelowThreshold() {
        let source = """
        enum S { static let title = "Settings" }
        """
        let results = scan(source, minConfidence: 0.5)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: Non-static excluded

    func testInstanceLetNotDetected() {
        let source = """
        struct Foo {
            let instanceTitle = "Not Static"
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 0)
    }

    func testTopLevelLetNotDetected() {
        // Top-level lets are more likely to be config / debug constants than UI strings
        let source = """
        let apiKey = "SomeKey"
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 0)
    }

    // MARK: False-positive filter still applies

    func testFalsePositivesExcluded() {
        let source = """
        enum Keys {
            static let analyticsKey  = "com.example.app.event"  // dotted identifier
            static let snakeCase     = "some_snake_case_key"     // snake_case
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 0,
            "FalsePositiveFilter should still exclude obvious non-UI strings")
    }

    func testEmptyStringExcluded() {
        let source = """
        enum S { static let empty = "" }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 0)
    }

    // MARK: Opt-out

    func testStaticConstantsDisabledByConfig() {
        let source = """
        enum Strings { static let title = "Hello" }
        """
        let scanner = StringScanner(
            minimumConfidence: 0.0,
            discoveryConfig: .init(staticConstants: false, indirectArgumentHints: false)
        )
        let results = scanner.scan(source: source, filePath: "Test.swift").detectedStrings
        XCTAssertEqual(results.count, 0)
    }

    // MARK: Inline suppression

    func testInlineSuppressionHonoured() {
        let source = """
        enum S {
            static let title = "Hello" // swiftl10n:ignore
        }
        """
        let results = scan(source)
        XCTAssertEqual(results.count, 0)
    }

    // MARK: Context

    func testContextIsStaticStringConstant() {
        let source = """
        enum S { static let msg = "Hello World" }
        """
        let results = scan(source)
        XCTAssertEqual(results.first?.context, .staticStringConstant)
    }
}

// MARK: - Indirect argument hints

final class IndirectArgumentHintTests: XCTestCase {

    private func diagnostics(_ source: String) -> [Diagnostic] {
        let scanner = StringScanner(
            minimumConfidence: 0.0,
            discoveryConfig: .init(staticConstants: false, indirectArgumentHints: true)
        )
        return scanner.scan(source: source, filePath: "Test.swift").diagnostics
    }

    private func suggestions(_ source: String) -> [Diagnostic] {
        diagnostics(source).filter { $0.severity == .suggestion }
    }

    // MARK: Basic emission

    func testHintEmittedForVariableInText() {
        let source = """
        struct V: View {
            var title: String
            var body: some View { Text(title) }
        }
        """
        XCTAssertEqual(suggestions(source).count, 1)
    }

    func testHintEmittedForMemberAccessInText() {
        let source = """
        struct V: View {
            var body: some View { Text(Titles.save) }
        }
        """
        XCTAssertEqual(suggestions(source).count, 1)
    }

    func testHintEmittedForVariableInButton() {
        let source = """
        struct V: View {
            var label: String
            var body: some View { Button(label) {} }
        }
        """
        XCTAssertEqual(suggestions(source).count, 1)
    }

    // MARK: No hint for string literals (already captured as detections)

    func testNoHintForStringLiteral() {
        let source = """
        struct V: View {
            var body: some View { Text("Hello") }
        }
        """
        XCTAssertEqual(suggestions(source).count, 0)
    }

    // MARK: Hint message content

    func testHintMessageContainsArgumentText() {
        let source = """
        struct V: View {
            var body: some View { Text(myTitle) }
        }
        """
        let hints = suggestions(source)
        XCTAssertEqual(hints.count, 1)
        XCTAssertTrue(hints[0].message.contains("myTitle"))
    }

    func testHintMessageContainsContextName() {
        let source = """
        struct V: View {
            var body: some View { Text(myTitle) }
        }
        """
        let hints = suggestions(source)
        XCTAssertTrue(hints[0].message.contains("Text"))
    }

    // MARK: Skip non-string expressions

    func testNoHintForNilArgument() {
        // Text doesn't actually take nil but at the syntactic level we should skip nil literals
        let source = "let _ = Button(nil) {}"
        XCTAssertEqual(suggestions(source).count, 0)
    }

    func testNoHintForBoolArgument() {
        let source = "let _ = Button(true) {}"
        XCTAssertEqual(suggestions(source).count, 0)
    }

    func testNoHintForIntArgument() {
        let source = "let _ = Button(42) {}"
        XCTAssertEqual(suggestions(source).count, 0)
    }

    func testNoHintForClosureArgument() {
        // Picker with a closure label — not a string
        let source = """
        Picker(selection: $val) { Text("A") } label: { Text("Pick") }
        """
        XCTAssertEqual(suggestions(source).count, 0)
    }

    // MARK: Severity

    func testHintIsSuggestionNotWarning() {
        let source = """
        struct V: View {
            var t: String
            var body: some View { Text(t) }
        }
        """
        let hints = diagnostics(source).filter { $0.severity == .suggestion }
        let warnings = diagnostics(source).filter { $0.severity == .warning }
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(warnings.count, 0,
            "Indirect argument hints must never elevate to warning severity")
    }

    // MARK: Opt-out

    func testHintsDisabledByConfig() {
        let source = """
        struct V: View {
            var t: String
            var body: some View { Text(t) }
        }
        """
        let scanner = StringScanner(
            minimumConfidence: 0.0,
            discoveryConfig: .init(staticConstants: false, indirectArgumentHints: false)
        )
        let result = scanner.scan(source: source, filePath: "Test.swift")
        let hints = result.diagnostics.filter { $0.severity == .suggestion }
        XCTAssertEqual(hints.count, 0)
    }
}

// MARK: - Config round-trip

final class StringDiscoveryConfigTests: XCTestCase {

    func testDefaultValues() {
        let config = SwiftL10nConfig.StringDiscoveryConfig()
        XCTAssertTrue(config.staticConstants)
        XCTAssertTrue(config.indirectArgumentHints)
    }

    func testDefaultsMatchStaticDefault() {
        XCTAssertEqual(SwiftL10nConfig.StringDiscoveryConfig(), .default)
    }

    func testDecodesFromYAML() throws {
        let yaml = """
        string_discovery:
          static_constants: false
          indirect_argument_hints: false
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertFalse(config.stringDiscovery.staticConstants)
        XCTAssertFalse(config.stringDiscovery.indirectArgumentHints)
    }

    func testDecodesWithDefaults() throws {
        let yaml = "sources: [\"Sources\"]"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertTrue(config.stringDiscovery.staticConstants)
        XCTAssertTrue(config.stringDiscovery.indirectArgumentHints)
    }
}
