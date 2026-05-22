import XCTest
import Yams
@testable import SwiftL10nCore

final class MergeStrategyTests: XCTestCase {

    // MARK: - FileRegionMerger.merge

    func testMergeReplacesContentBetweenMarkers() {
        let existing = """
        // Manual header

        // MARK: - SwiftL10n Generated BEGIN
        enum i18n { static func oldTitle() -> String { "" } }
        // MARK: - SwiftL10n Generated END

        // Manual footer
        """
        let newContent = "enum i18n { static func newTitle() -> String { \"\" } }"

        let result = FileRegionMerger.merge(existing: existing, newContent: newContent)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("newTitle"), "New content should be present")
        XCTAssertFalse(result!.contains("oldTitle"), "Old content should be replaced")
        XCTAssertTrue(result!.contains("// Manual header"), "Content above BEGIN must be preserved")
        XCTAssertTrue(result!.contains("// Manual footer"), "Content below END must be preserved")
    }

    func testMergePreservesManualExtensions() {
        let existing = """
        // MARK: - SwiftL10n Generated BEGIN
        enum i18n { }
        // MARK: - SwiftL10n Generated END

        extension i18n.Common {
            static var customHelper: String { "custom" }
        }
        """
        let result = FileRegionMerger.merge(existing: existing, newContent: "enum i18n { static func save() -> String { \"\" } }")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("customHelper"), "Manual extension below END must be preserved")
        XCTAssertTrue(result!.contains("save()"), "New generated content should be present")
    }

    func testMergeReturnsNilWhenNoMarkers() {
        let existing = "enum i18n { }"
        let result = FileRegionMerger.merge(existing: existing, newContent: "new content")
        XCTAssertNil(result, "Should return nil when no markers — caller uses wrap()")
    }

    func testMergeReturnsNilWhenOnlyBeginMarker() {
        let existing = "// MARK: - SwiftL10n Generated BEGIN\nenum i18n { }"
        let result = FileRegionMerger.merge(existing: existing, newContent: "new")
        XCTAssertNil(result)
    }

    func testMergeReturnsNilWhenMarkersReversed() {
        let existing = """
        // MARK: - SwiftL10n Generated END
        // MARK: - SwiftL10n Generated BEGIN
        """
        let result = FileRegionMerger.merge(existing: existing, newContent: "new")
        XCTAssertNil(result)
    }

    func testMergeHandlesWhitespaceAroundMarkers() {
        let existing = """
           // MARK: - SwiftL10n Generated BEGIN
        old content
           // MARK: - SwiftL10n Generated END
        """
        let result = FileRegionMerger.merge(existing: existing, newContent: "new content")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("new content"))
        XCTAssertFalse(result!.contains("old content"))
    }

    // MARK: - FileRegionMerger.wrap

    func testWrapAddsBeginAndEndMarkers() {
        let content = "enum i18n { }"
        let wrapped = FileRegionMerger.wrap(content)
        XCTAssertTrue(wrapped.contains(FileRegionMerger.beginMarker))
        XCTAssertTrue(wrapped.contains(FileRegionMerger.endMarker))
        XCTAssertTrue(wrapped.contains(content))
        let beginIdx = wrapped.range(of: FileRegionMerger.beginMarker)!.lowerBound
        let endIdx   = wrapped.range(of: FileRegionMerger.endMarker)!.lowerBound
        XCTAssertLessThan(beginIdx, endIdx, "BEGIN must precede END")
    }

    func testWrappedContentCanBeReMerged() {
        let original = "enum i18n { static func first() -> String { \"\" } }"
        let wrapped  = FileRegionMerger.wrap(original)

        let updated  = "enum i18n { static func second() -> String { \"\" } }"
        let remerged = FileRegionMerger.merge(existing: wrapped, newContent: updated)
        XCTAssertNotNil(remerged)
        XCTAssertTrue(remerged!.contains("second()"))
        XCTAssertFalse(remerged!.contains("first()"))
    }

    // MARK: - Config decoding

    func testDefaultMergeStrategyIsOverwrite() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.output.mergeStrategy, .overwrite)
    }

    func testDecodeRegionMergeStrategy() throws {
        let yaml = """
        sources: [Sources]
        output:
          merge_strategy: region
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.output.mergeStrategy, .region)
    }

    func testOverwriteStrategyDecodesExplicitly() throws {
        let yaml = """
        sources: [Sources]
        output:
          merge_strategy: overwrite
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.output.mergeStrategy, .overwrite)
    }

    // MARK: - Round-trip

    func testMergeRoundTripPreservesManualCode() {
        let manualExtension = """

        // MARK: - Manual
        extension i18n.Common {
            static var legacyKey: String { "value" }
        }
        """

        let generatedV1 = "enum i18n { static func titleV1() -> String { \"\" } }"
        let firstWrite  = FileRegionMerger.wrap(generatedV1) + manualExtension

        let generatedV2 = "enum i18n { static func titleV2() -> String { \"\" } }"
        let secondWrite = FileRegionMerger.merge(existing: firstWrite, newContent: generatedV2)!

        XCTAssertTrue(secondWrite.contains("titleV2()"), "New generated API should appear")
        XCTAssertFalse(secondWrite.contains("titleV1()"), "Old generated API should be replaced")
        XCTAssertTrue(secondWrite.contains("legacyKey"), "Manual extension must survive regeneration")
    }
}
