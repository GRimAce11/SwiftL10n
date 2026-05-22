import XCTest
@testable import SwiftL10nCore

final class SuppressionIndexTests: XCTestCase {

    private func loc(_ file: String, _ line: Int, _ column: Int) -> SourceLocation {
        SourceLocation(file: file, line: line, column: column)
    }

    // MARK: - Basic lookup

    func testEmptyIndexSuppressesNothing() {
        let index = SuppressionIndex()
        XCTAssertFalse(index.isSuppressed(loc("A.swift", 1, 1)))
    }

    func testContainedLocationIsSuppressed() {
        let location = loc("A.swift", 5, 10)
        let index = SuppressionIndex(locations: [location])
        XCTAssertTrue(index.isSuppressed(location))
    }

    func testDifferentFileNotSuppressed() {
        let index = SuppressionIndex(locations: [loc("A.swift", 5, 10)])
        XCTAssertFalse(index.isSuppressed(loc("B.swift", 5, 10)))
    }

    func testDifferentLineNotSuppressed() {
        let index = SuppressionIndex(locations: [loc("A.swift", 5, 10)])
        XCTAssertFalse(index.isSuppressed(loc("A.swift", 6, 10)))
    }

    func testDifferentColumnNotSuppressed() {
        let index = SuppressionIndex(locations: [loc("A.swift", 5, 10)])
        XCTAssertFalse(index.isSuppressed(loc("A.swift", 5, 11)))
    }

    // MARK: - Properties

    func testIsEmpty() {
        XCTAssertTrue(SuppressionIndex.empty.isEmpty)
        XCTAssertFalse(SuppressionIndex(locations: [loc("A.swift", 1, 1)]).isEmpty)
    }

    func testCount() {
        let index = SuppressionIndex(locations: [
            loc("A.swift", 1, 1),
            loc("A.swift", 2, 1),
            loc("B.swift", 1, 1)
        ])
        XCTAssertEqual(index.count, 3)
    }

    // MARK: - Merging

    func testMergingCombinesLocations() {
        let a = SuppressionIndex(locations: [loc("A.swift", 1, 1)])
        let b = SuppressionIndex(locations: [loc("B.swift", 2, 5)])
        let merged = a.merging(b)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.isSuppressed(loc("A.swift", 1, 1)))
        XCTAssertTrue(merged.isSuppressed(loc("B.swift", 2, 5)))
    }

    func testMergingWithEmptyIsIdentity() {
        let original = SuppressionIndex(locations: [loc("A.swift", 1, 1)])
        let merged = original.merging(.empty)
        XCTAssertEqual(merged.count, original.count)
    }

    // MARK: - Integration with ExistingLocalizationDetector

    func testDetectorSuppressionsFlowIntoIndex() {
        let source = #"""
        let x = NSLocalizedString("Save", comment: "")
        let y = NSLocalizedString("Cancel", comment: "")
        """#
        let config = ExistingLocalizationDetector.Config(
            patterns: [],
            excludeArgumentsOf: ["NSLocalizedString"]
        )
        let result = ExistingLocalizationDetector(config: config).detect(
            source: source,
            filePath: "Test.swift"
        )
        let index = SuppressionIndex(locations: result.suppressionLocations)
        XCTAssertEqual(index.count, 4, "4 string args across 2 NSLocalizedString calls")
        XCTAssertFalse(index.isEmpty)
    }
}
