import XCTest
@testable import SwiftL10nCore

final class CodeGeneratorTests: XCTestCase {

    private let generator = CodeGenerator()

    // MARK: - Deduplication

    func testDecorativeVariantIsDropped() {
        // "Continue →" and "Continue" must produce ONE function, not two
        let ns = namespace(values: ["Continue", "Continue →"])
        let output = generator.generate(namespaces: [ns])
        XCTAssertEqual(occurrences(of: "static func continue", in: output), 1,
            "Two strings that normalise to the same name must produce exactly one function")
    }

    func testCleanerStringWins() {
        // The function body must use "Continue" (no arrow), not "Continue →"
        let ns = namespace(values: ["Continue →", "Continue"])
        let output = generator.generate(namespaces: [ns])
        XCTAssertTrue(output.contains("\"Continue\""),
            "The cleaner string (without decoration) must be the localisation key")
        XCTAssertFalse(output.contains("\"Continue →\""),
            "The decorated variant must not appear in the generated output")
    }

    func testArrowInSeparatorListProducesCleanName() {
        // "Next →" alone must generate nextButtonTitle, not "nextButtonTitle" with arrow noise
        let ns = namespace(values: ["Next →"])
        let output = generator.generate(namespaces: [ns])
        XCTAssertTrue(output.contains("func nextButtonTitle()"),
            "Arrow should be stripped when building the function name")
    }

    func testDifferentStringsWithSameNameGetDeduplicatedToFirst() {
        // "Done!" and "Done" — both clean up to "done". Keep the cleaner one.
        let ns = namespace(values: ["Done!", "Done"])
        let output = generator.generate(namespaces: [ns])
        XCTAssertEqual(occurrences(of: "static func done", in: output), 1)
        XCTAssertTrue(output.contains("\"Done\""))
        XCTAssertFalse(output.contains("\"Done!\""))
    }

    func testUniqueNamesAreAllGenerated() {
        let ns = namespace(values: ["Save", "Cancel", "Delete"])
        let output = generator.generate(namespaces: [ns])
        XCTAssertEqual(occurrences(of: "static func ", in: output), 3)
    }

    func testInterpolatedStringNotDedupedButStillExcluded() {
        // "Continue" + "Continue {…}" (interpolated) → only "Continue" generated
        let plain = makeString("Continue", hasInterpolation: false)
        let interp = makeString("Continue {…}", hasInterpolation: true)
        let ns = Namespace(name: "Test", sourceFile: "t.swift", strings: [plain, interp])
        let output = generator.generate(namespaces: [ns])
        XCTAssertEqual(occurrences(of: "static func continue", in: output), 1)
        XCTAssertFalse(output.contains("{…}"))
    }

    // MARK: - Helpers

    private func namespace(values: [String]) -> Namespace {
        Namespace(name: "Test", sourceFile: "t.swift", strings: values.map { makeString($0) })
    }

    private func makeString(_ value: String, hasInterpolation: Bool = false) -> DetectedString {
        DetectedString(
            value: value,
            location: SourceLocation(file: "t.swift", line: 1, column: 1),
            context: .buttonLabel,
            confidence: 0.95,
            hasInterpolation: hasInterpolation
        )
    }

    private func occurrences(of substring: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
