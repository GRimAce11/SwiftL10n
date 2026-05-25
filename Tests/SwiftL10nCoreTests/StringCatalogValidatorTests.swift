import XCTest
@testable import SwiftL10nCore

final class StringCatalogValidatorTests: XCTestCase {

    private let validator = StringCatalogValidator()

    private func catalog(keys: [String]) -> StringCatalog {
        let entries = Dictionary(uniqueKeysWithValues: keys.map {
            ($0, StringCatalog.Entry(comment: nil, sourceValue: $0, translationCount: 1))
        })
        return StringCatalog(sourceLanguage: "en", entries: entries, catalogURL: nil)
    }

    private func namespace(name: String, values: [String]) -> Namespace {
        let strings = values.map { value in
            DetectedString(
                value: value,
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                context: .textView,
                confidence: 0.95
            )
        }
        return Namespace(name: name, sourceFile: "Test.swift", strings: strings)
    }

    // MARK: - Missing from catalog

    func testNoMissingWhenAllKeysPresent() {
        let ns = namespace(name: "Settings", values: ["Save", "Delete"])
        let cat = catalog(keys: ["Save", "Delete", "Cancel"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.missingCount, 0)
    }

    func testMissingKeyDetected() {
        let ns = namespace(name: "Settings", values: ["Save", "New String"])
        let cat = catalog(keys: ["Save"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.missingCount, 1)
        XCTAssertEqual(result.missingFromCatalog[0].value, "New String")
    }

    func testMissingEntryCarriesLocation() {
        let strings = [DetectedString(
            value: "Missing",
            location: SourceLocation(file: "View.swift", line: 10, column: 5),
            context: .textView,
            confidence: 0.95
        )]
        let ns = Namespace(name: "Test", sourceFile: "View.swift", strings: strings)
        let cat = catalog(keys: ["Other"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.missingFromCatalog[0].locations.first?.file, "View.swift")
        XCTAssertEqual(result.missingFromCatalog[0].locations.first?.line, 10)
    }

    func testMissingEntrySortedAlphabetically() {
        let ns = namespace(name: "N", values: ["Zebra", "Apple", "Mango"])
        // Catalog has an unrelated key so validation fires (non-empty catalog)
        let cat = catalog(keys: ["ExistingKey"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.missingFromCatalog.map(\.value), ["Apple", "Mango", "Zebra"])
    }

    // MARK: - Orphaned in catalog

    func testOrphanedKeyDetected() {
        let ns = namespace(name: "Settings", values: ["Save"])
        let cat = catalog(keys: ["Save", "OldDeadKey"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.orphanedCount, 1)
        XCTAssertEqual(result.orphanedInCatalog[0], "OldDeadKey")
    }

    func testNoOrphanedWhenAllKeysReferenced() {
        let ns = namespace(name: "N", values: ["Save", "Delete"])
        let cat = catalog(keys: ["Save", "Delete"])
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.orphanedCount, 0)
    }

    // MARK: - Interpolated strings skipped

    func testInterpolatedStringsNotValidated() {
        let interpolated = DetectedString(
            value: "Hello {…}!",
            location: SourceLocation(file: "f", line: 1, column: 1),
            context: .textView,
            confidence: 0.9,
            hasInterpolation: true
        )
        let ns = Namespace(name: "N", sourceFile: "f", strings: [interpolated])
        let cat = catalog(keys: [])  // empty catalog — interpolated string should NOT be flagged missing
        let result = validator.validate(namespaces: [ns], against: cat)
        XCTAssertEqual(result.missingCount, 0, "Interpolated strings must not be validated against catalog")
    }

    // MARK: - Empty catalog

    func testEmptyCatalogSkipsValidation() {
        let ns = namespace(name: "N", values: ["Save"])
        let result = validator.validate(namespaces: [ns], against: .empty)
        XCTAssertEqual(result.missingCount, 0)
        XCTAssertEqual(result.orphanedCount, 0)
    }

    // MARK: - Multiple namespaces

    func testSameValueInMultipleNamespacesCountedOnce() {
        let ns1 = namespace(name: "A", values: ["Save"])
        let ns2 = namespace(name: "B", values: ["Save"])
        // Catalog has an unrelated key so validation fires
        let cat = catalog(keys: ["Cancel"])
        let result = validator.validate(namespaces: [ns1, ns2], against: cat)
        XCTAssertEqual(result.missingCount, 1, "Same value in two namespaces = one missing entry")
    }
}
