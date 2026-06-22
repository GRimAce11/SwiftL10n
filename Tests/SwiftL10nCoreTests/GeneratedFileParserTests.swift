import XCTest
@testable import SwiftL10nCore

/// Covers the lossy-regeneration fix: a generated `i18n.swift` is a source of
/// truth, so accessors whose literals have been migrated to call sites survive
/// regeneration (reference-aware), and genuinely-dead ones are pruned.
final class GeneratedFileParserTests: XCTestCase {

    private let generator = CodeGenerator()

    // MARK: - Round-trip

    func testGenerateThenParseRecoversAccessors() {
        let ns = Namespace(name: "AdLibrary", sourceFile: "AdLibraryView.swift", strings: [
            makeString("Title", context: .textView),
            makeString("Save", context: .buttonLabel),
        ])
        let generated = generator.generate(namespaces: [ns])

        let parsed = GeneratedFileParser.parse(generated, rootEnumName: "i18n")
        let keys = Set(parsed.map(\.referenceKey))
        XCTAssertEqual(keys, ["AdLibrary.title", "AdLibrary.saveButtonTitle"])
    }

    func testRoundTripIsByteIdentical() {
        // Generate → parse → regenerate from preserved alone must reproduce the file.
        let ns = Namespace(name: "MySpace", sourceFile: "MySpaceView.swift", strings: [
            makeString("Header", context: .textView),
            makeString("Continue", context: .buttonLabel),   // keyword-adjacent name
        ])
        let original = generator.generate(namespaces: [ns])

        let preserved = GeneratedFileParser.parse(original, rootEnumName: "i18n")
        let regenerated = generator.generate(namespaces: [], preserved: preserved)

        XCTAssertEqual(regenerated, original,
            "A parse → regenerate round-trip must be lossless and byte-identical")
    }

    func testKeywordFunctionNameRoundTrips() {
        // "Return" → reserved keyword → must be backticked in source and on re-emit.
        let ns = Namespace(name: "Nav", sourceFile: "Nav.swift", strings: [
            makeString("Return", context: .textView),
        ])
        let original = generator.generate(namespaces: [ns])
        XCTAssertTrue(original.contains("static func `return`()"))

        let preserved = GeneratedFileParser.parse(original, rootEnumName: "i18n")
        XCTAssertEqual(preserved.first?.funcName, "return", "Backticks must be stripped from the bare key")
        XCTAssertEqual(generator.generate(namespaces: [], preserved: preserved), original)
    }

    func testEscapedValuesRoundTrip() {
        let ns = Namespace(name: "Quotes", sourceFile: "Q.swift", strings: [
            makeString(#"Say "hi" \ now"#, context: .textView),
        ])
        let original = generator.generate(namespaces: [ns])
        let preserved = GeneratedFileParser.parse(original, rootEnumName: "i18n")
        XCTAssertEqual(generator.generate(namespaces: [], preserved: preserved), original,
            "Quotes and backslashes must survive the parse → emit round-trip without double-escaping")
    }

    // MARK: - The reported bug: migrated literal must not be dropped

    func testMigratedNamespaceSurvivesRegeneration() {
        // 1. First generation: AdLibrary has a literal.
        let v1 = generator.generate(namespaces: [
            Namespace(name: "AdLibrary", sourceFile: "AdLibraryView.swift", strings: [
                makeString("Sponsored", context: .textView),
            ]),
            Namespace(name: "Home", sourceFile: "HomeView.swift", strings: [
                makeString("Welcome", context: .textView),
            ]),
        ])

        // 2. The AdLibrary call site is migrated → the literal is gone from source,
        //    so the rescan produces no AdLibrary namespace. But the accessor is
        //    still referenced (i18n.AdLibrary.sponsored).
        let referenced: Set<String> = ["AdLibrary.sponsored"]
        let preserved = GeneratedFileParser.preserving(
            GeneratedFileParser.parse(v1, rootEnumName: "i18n"),
            referencedIn: referenced
        )

        let v2 = generator.generate(
            namespaces: [
                Namespace(name: "Home", sourceFile: "HomeView.swift", strings: [
                    makeString("Welcome", context: .textView),
                ]),
            ],
            preserved: preserved
        )

        XCTAssertTrue(v2.contains("enum AdLibrary"),
            "Regeneration must NOT drop a namespace whose literal was migrated to an accessor")
        XCTAssertTrue(v2.contains("static func sponsored()"))
        XCTAssertTrue(v2.contains("enum Home"))
    }

    func testUnreferencedAccessorIsPruned() {
        let v1 = generator.generate(namespaces: [
            Namespace(name: "Dead", sourceFile: "Dead.swift", strings: [
                makeString("Obsolete", context: .textView),
            ]),
        ])
        // No references at all → truly dead → pruned.
        let preserved = GeneratedFileParser.preserving(
            GeneratedFileParser.parse(v1, rootEnumName: "i18n"),
            referencedIn: []
        )
        XCTAssertTrue(preserved.isEmpty)

        let v2 = generator.generate(namespaces: [], preserved: preserved)
        XCTAssertFalse(v2.contains("enum Dead"))
        XCTAssertFalse(v2.contains("Obsolete"))
    }

    func testScannedStringWinsOverPreservedOnCollision() {
        // Same funcName present in both scan and preserved: scan must win (live value).
        let scanned = Namespace(name: "Shared", sourceFile: "S.swift", strings: [
            makeString("New Value", context: .textView),
        ])
        let preserved = [PreservedAccessor(
            namespace: "Shared",
            funcName: "newValue",
            escapedValue: "Stale Value",
            escapedComment: "Shared: Text — Stale Value"
        )]
        let output = generator.generate(namespaces: [scanned], preserved: preserved)
        XCTAssertEqual(occurrences(of: "static func newValue()", in: output), 1,
            "A funcName present in both must be emitted exactly once")
        XCTAssertTrue(output.contains("\"New Value\""))
        XCTAssertFalse(output.contains("Stale Value"))
    }

    // MARK: - Region merge

    func testParserReadsOnlyInsideRegionMarkers() {
        let inside = generator.generate(namespaces: [
            Namespace(name: "Owned", sourceFile: "O.swift", strings: [makeString("Owned", context: .textView)]),
        ])
        let file = """
        // Manual header
        extension i18n.Manual {
            static func handWritten() -> String { "manual" }
        }

        \(FileRegionMerger.beginMarker)
        \(inside)
        \(FileRegionMerger.endMarker)

        // Manual footer
        """
        let parsed = GeneratedFileParser.parse(file, rootEnumName: "i18n")
        let keys = Set(parsed.map(\.referenceKey))
        XCTAssertEqual(keys, ["Owned.owned"],
            "Manual extensions outside the markers must not be parsed as generated accessors")
    }

    // MARK: - Helpers

    private func makeString(_ value: String, context: DetectionContext) -> DetectedString {
        DetectedString(
            value: value,
            location: SourceLocation(file: "t.swift", line: 1, column: 1),
            context: context,
            confidence: 0.95
        )
    }

    private func occurrences(of substring: String, in text: String) -> Int {
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: substring, range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }
}
