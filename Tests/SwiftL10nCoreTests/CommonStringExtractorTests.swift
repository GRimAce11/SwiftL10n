import XCTest
@testable import SwiftL10nCore

final class CommonStringExtractorTests: XCTestCase {

    private let extractor = CommonStringExtractor()

    // MARK: - No shared strings

    func testNoSharedStringsReturnsOriginalNamespaces() {
        let ns1 = makeNamespace("Settings", values: ["Delete Account", "Save"])
        let ns2 = makeNamespace("Home", values: ["Welcome Back", "Get Started"])

        let result = extractor.extract(from: [ns1, ns2])

        XCTAssertNil(result.common)
        XCTAssertEqual(result.namespaces.count, 2)
    }

    // MARK: - Shared string lifted to Common

    func testSharedStringMovedToCommon() {
        let ns1 = makeNamespace("Settings", values: ["Save", "Delete Account"])
        let ns2 = makeNamespace("Profile",  values: ["Save", "Edit"])

        let result = extractor.extract(from: [ns1, ns2])

        XCTAssertNotNil(result.common)
        let commonValues = result.common!.strings.map(\.value)
        XCTAssertTrue(commonValues.contains("Save"))
    }

    func testSharedStringRemovedFromOriginalNamespaces() {
        let ns1 = makeNamespace("Settings", values: ["Save", "Delete Account"])
        let ns2 = makeNamespace("Profile",  values: ["Save", "Edit"])

        let result = extractor.extract(from: [ns1, ns2])

        for ns in result.namespaces {
            XCTAssertFalse(ns.strings.map(\.value).contains("Save"),
                           "\(ns.name) should not contain 'Save' after extraction")
        }
    }

    func testUniqueStringsStayInOriginalNamespace() {
        let ns1 = makeNamespace("Settings", values: ["Save", "Delete Account"])
        let ns2 = makeNamespace("Profile",  values: ["Save", "Edit"])

        let result = extractor.extract(from: [ns1, ns2])

        let settingsValues = result.namespaces.first(where: { $0.name == "Settings" })?.strings.map(\.value) ?? []
        XCTAssertTrue(settingsValues.contains("Delete Account"))

        let profileValues = result.namespaces.first(where: { $0.name == "Profile" })?.strings.map(\.value) ?? []
        XCTAssertTrue(profileValues.contains("Edit"))
    }

    // MARK: - Multiple shared strings

    func testMultipleSharedStrings() {
        let ns1 = makeNamespace("A", values: ["Save", "Cancel", "Unique A"])
        let ns2 = makeNamespace("B", values: ["Save", "Cancel", "Unique B"])

        let result = extractor.extract(from: [ns1, ns2])

        let commonValues = result.common?.strings.map(\.value) ?? []
        XCTAssertTrue(commonValues.contains("Save"))
        XCTAssertTrue(commonValues.contains("Cancel"))
        XCTAssertFalse(commonValues.contains("Unique A"))
        XCTAssertFalse(commonValues.contains("Unique B"))
    }

    // MARK: - Empty namespace pruning

    func testNamespaceWithOnlySharedStringsIsRemoved() {
        // ns1 has ONLY "Save" — after extraction it should be dropped
        let ns1 = makeNamespace("OnlyShared", values: ["Save"])
        let ns2 = makeNamespace("Mixed",      values: ["Save", "Delete"])

        let result = extractor.extract(from: [ns1, ns2])

        XCTAssertNil(result.namespaces.first(where: { $0.name == "OnlyShared" }),
                     "Namespace with only shared strings should be removed")
        XCTAssertNotNil(result.namespaces.first(where: { $0.name == "Mixed" }))
    }

    // MARK: - Common namespace name

    func testCommonNamespaceIsNamedCorrectly() {
        let ns1 = makeNamespace("A", values: ["Save"])
        let ns2 = makeNamespace("B", values: ["Save"])

        let result = extractor.extract(from: [ns1, ns2])

        XCTAssertEqual(result.common?.name, "Common")
    }

    // MARK: - Origins map

    func testOriginsMapContainsSourceNamespaces() {
        let ns1 = makeNamespace("Settings", values: ["Save"])
        let ns2 = makeNamespace("Profile",  values: ["Save"])

        let result = extractor.extract(from: [ns1, ns2])

        let origins = result.origins["Save"] ?? []
        XCTAssertTrue(origins.contains("Settings"))
        XCTAssertTrue(origins.contains("Profile"))
    }

    // MARK: - Single namespace — no extraction

    func testSingleNamespaceProducesNoCommon() {
        let ns = makeNamespace("Settings", values: ["Save", "Cancel"])

        let result = extractor.extract(from: [ns])

        XCTAssertNil(result.common)
        XCTAssertEqual(result.namespaces.count, 1)
    }

    // MARK: - Interpolated strings are never common

    func testInterpolatedStringsNotExtracted() {
        let s1 = makeString("Hello {…}", hasInterpolation: true)
        let s2 = makeString("Hello {…}", hasInterpolation: true)
        let ns1 = Namespace(name: "A", sourceFile: "A.swift", strings: [s1])
        let ns2 = Namespace(name: "B", sourceFile: "B.swift", strings: [s2])

        let result = extractor.extract(from: [ns1, ns2])

        XCTAssertNil(result.common, "Interpolated strings must not be extracted to Common")
    }

    // MARK: - Helpers

    private func makeNamespace(_ name: String, values: [String]) -> Namespace {
        Namespace(name: name, sourceFile: "\(name).swift", strings: values.map { makeString($0) })
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
}
