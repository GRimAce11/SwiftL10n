import XCTest
@testable import SwiftL10nCore

final class InterpolationTests: XCTestCase {

    private let scanner = StringScanner()

    // MARK: - Detection

    func testInterpolatedStringIsDetected() {
        let result = scanner.scan(source: #"Text("Hello \(name)!")"#, filePath: "t.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
    }

    func testInterpolatedStringHasFlag() {
        let result = scanner.scan(source: #"Text("Hello \(name)!")"#, filePath: "t.swift")
        XCTAssertTrue(result.detectedStrings[0].hasInterpolation)
    }

    func testInterpolatedStringValueContainsMarker() {
        let result = scanner.scan(source: #"Text("Hello \(name)!")"#, filePath: "t.swift")
        let value = result.detectedStrings[0].value
        XCTAssertTrue(value.contains("{…}"), "Expected interpolation marker in value, got: \(value)")
    }

    func testInterpolatedStringEmitsWarning() {
        let result = scanner.scan(source: #"Text("Welcome \(user)!")"#, filePath: "t.swift")
        let warnings = result.diagnostics.filter { $0.severity == .warning }
        XCTAssertFalse(warnings.isEmpty, "Expected at least one warning for interpolated string")
    }

    func testInterpolationWarningMessageMentionsString() {
        let result = scanner.scan(source: #"Text("Total: \(count) items")"#, filePath: "t.swift")
        let warning = result.diagnostics.first(where: { $0.severity == .warning })
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.message.contains("Interpolated"), "Warning should mention interpolation")
    }

    // MARK: - Plain string has no warning

    func testPlainStringProducesNoWarning() {
        let result = scanner.scan(source: #"Text("Settings")"#, filePath: "t.swift")
        let warnings = result.diagnostics.filter { $0.severity == .warning }
        XCTAssertTrue(warnings.isEmpty)
    }

    func testPlainStringHasNoInterpolationFlag() {
        let result = scanner.scan(source: #"Text("Settings")"#, filePath: "t.swift")
        XCTAssertFalse(result.detectedStrings[0].hasInterpolation)
    }

    // MARK: - Multiple segments

    func testMultipleInterpolationsInOneString() {
        let result = scanner.scan(
            source: #"Text("Hello \(first) \(last), you have \(count) messages")"#,
            filePath: "t.swift"
        )
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertTrue(result.detectedStrings[0].hasInterpolation)
        let value = result.detectedStrings[0].value
        // Template should have multiple markers
        XCTAssertEqual(value.components(separatedBy: "{…}").count - 1, 3)
    }

    // MARK: - Mixed file

    func testMixedFileCountsCorrectly() {
        let result = scanner.scan(
            source: TestFixtures.interpolationMix,
            filePath: "WelcomeView.swift"
        )
        let interpolated = result.detectedStrings.filter(\.hasInterpolation)
        let plain = result.detectedStrings.filter { !$0.hasInterpolation }
        // "Welcome Back" and "Continue" and "Welcome" are plain; "Hello \(name)!" and "You have \(count)…" are interpolated
        XCTAssertEqual(interpolated.count, 2, "Expected 2 interpolated strings")
        XCTAssertEqual(plain.count, 3, "Expected 3 plain strings")
    }

    // MARK: - Code generator skips interpolated

    func testCodeGeneratorSkipsInterpolatedStrings() {
        let result = scanner.scan(
            source: TestFixtures.interpolationMix,
            filePath: "WelcomeView.swift"
        )
        let namespace = Namespace(name: "Welcome", sourceFile: "WelcomeView.swift", strings: result.detectedStrings)
        let output = CodeGenerator().generate(namespaces: [namespace])
        XCTAssertFalse(output.contains("{…}"), "Code generator must not emit interpolation markers")
    }
}
