import XCTest
@testable import SwiftL10nCore

final class DuplicateLocalizationTests: XCTestCase {

    private let analyzer = DuplicateLocalizationAnalyzer()

    // MARK: - Helpers

    private func catalog(entries: [(key: String, value: String)]) -> StringCatalog {
        let mapped = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.key, StringCatalog.Entry(comment: nil, sourceValue: $0.value, translationCount: 1))
        })
        return StringCatalog(sourceLanguage: "en", entries: mapped, catalogURL: nil)
    }

    private func namespace(name: String, values: [String], file: String = "F.swift") -> Namespace {
        let strings = values.map { value in
            DetectedString(
                value: value,
                location: SourceLocation(file: file, line: 1, column: 1),
                context: .textView,
                confidence: 0.95
            )
        }
        return Namespace(name: name, sourceFile: file, strings: strings)
    }

    // MARK: - Catalog duplicate analysis

    func testCatalogDuplicatesDetected() {
        let cat = catalog(entries: [("cancel_button", "Cancel"), ("cancel_nav", "Cancel")])
        let groups = analyzer.analyzeCatalog(cat)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sharedValue, "Cancel")
        XCTAssertEqual(groups[0].keys.sorted(), ["cancel_button", "cancel_nav"])
    }

    func testNoDuplicatesWhenAllValuesUnique() {
        let cat = catalog(entries: [("save", "Save"), ("cancel", "Cancel"), ("delete", "Delete")])
        XCTAssertTrue(analyzer.analyzeCatalog(cat).isEmpty)
    }

    func testCatalogDuplicatesSortedByValue() {
        let cat = catalog(entries: [
            ("z_key", "Zebra"), ("z_key2", "Zebra"),
            ("a_key", "Apple"), ("a_key2", "Apple"),
        ])
        let groups = analyzer.analyzeCatalog(cat)
        XCTAssertEqual(groups.map(\.sharedValue), ["Apple", "Zebra"])
    }

    func testEmptyCatalogReturnsEmpty() {
        XCTAssertTrue(analyzer.analyzeCatalog(.empty).isEmpty)
    }

    func testCatalogFallsBackToKeyWhenNoSourceValue() {
        // Entry with no sourceValue — key is used as value
        let entries: [String: StringCatalog.Entry] = [
            "my_key": StringCatalog.Entry(comment: nil, sourceValue: nil, translationCount: 0),
            "my_key2": StringCatalog.Entry(comment: nil, sourceValue: nil, translationCount: 0),
        ]
        let cat = StringCatalog(sourceLanguage: "en", entries: entries, catalogURL: nil)
        // Two different keys with nil sourceValue — each falls back to its own key → no duplicates
        XCTAssertTrue(analyzer.analyzeCatalog(cat).isEmpty)
    }

    // MARK: - Namespace duplicate analysis

    func testNamespaceDuplicatesDetectedAcrossFiles() {
        let ns1 = namespace(name: "Settings", values: ["Save"], file: "SettingsView.swift")
        let ns2 = namespace(name: "Profile",  values: ["Save"], file: "ProfileView.swift")
        let groups = analyzer.analyzeNamespaces([ns1, ns2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].value, "Save")
        XCTAssertEqual(groups[0].occurrences.count, 2)
    }

    func testSingleNamespaceNoDuplicate() {
        let ns = namespace(name: "Settings", values: ["Save", "Delete"])
        XCTAssertTrue(analyzer.analyzeNamespaces([ns]).isEmpty)
    }

    func testInterpolatedStringsExcludedFromNamespaceAnalysis() {
        let interpolated = DetectedString(
            value: "Hello {…}!",
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            context: .textView,
            confidence: 0.9,
            hasInterpolation: true
        )
        let ns1 = Namespace(name: "A", sourceFile: "A.swift", strings: [interpolated])
        let ns2 = Namespace(name: "B", sourceFile: "B.swift", strings: [interpolated])
        XCTAssertTrue(analyzer.analyzeNamespaces([ns1, ns2]).isEmpty)
    }

    func testNamespaceGroupsSortedAlphabetically() {
        let ns1 = namespace(name: "A", values: ["Zebra", "Apple"])
        let ns2 = namespace(name: "B", values: ["Zebra", "Apple"])
        let groups = analyzer.analyzeNamespaces([ns1, ns2])
        XCTAssertEqual(groups.map(\.value), ["Apple", "Zebra"])
    }
}
