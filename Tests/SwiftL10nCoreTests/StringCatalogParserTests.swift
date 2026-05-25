import XCTest
@testable import SwiftL10nCore

final class StringCatalogParserTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogParserTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func write(_ json: String, name: String = "Localizable.xcstrings") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let minimalJSON = """
    {
      "sourceLanguage": "en",
      "strings": {
        "Delete Account": {
          "comment": "Danger zone",
          "localizations": {
            "en": { "stringUnit": { "state": "translated", "value": "Delete Account" } },
            "fr": { "stringUnit": { "state": "translated", "value": "Supprimer le compte" } }
          }
        },
        "Save": {
          "localizations": {
            "en": { "stringUnit": { "state": "translated", "value": "Save" } }
          }
        }
      }
    }
    """

    // MARK: - Parse keys

    func testParsesKeysFromXCStrings() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertEqual(catalog.keys, ["Delete Account", "Save"])
    }

    func testParsesSourceValue() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertEqual(catalog.entries["Delete Account"]?.sourceValue, "Delete Account")
        XCTAssertEqual(catalog.entries["Save"]?.sourceValue, "Save")
    }

    func testParsesTranslationCount() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertEqual(catalog.entries["Delete Account"]?.translationCount, 2)
        XCTAssertEqual(catalog.entries["Save"]?.translationCount, 1)
    }

    func testParsesComment() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertEqual(catalog.entries["Delete Account"]?.comment, "Danger zone")
        XCTAssertNil(catalog.entries["Save"]?.comment)
    }

    func testLanguageCount() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertEqual(catalog.languageCount, 2)
    }

    // MARK: - Missing localizations fallback

    func testMissingLocalizationsFallsBackToKey() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "strings": {
            "New Unextracted String": {}
          }
        }
        """
        let url = try write(json)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertTrue(catalog.contains(key: "New Unextracted String"))
        XCTAssertEqual(catalog.entries["New Unextracted String"]?.sourceValue, "New Unextracted String")
    }

    // MARK: - contains / keys

    func testContainsReturnsTrueForPresentKey() throws {
        let url = try write(minimalJSON)
        let catalog = try StringCatalogParser.parse(url: url)
        XCTAssertTrue(catalog.contains(key: "Save"))
        XCTAssertFalse(catalog.contains(key: "Missing Key"))
    }

    // MARK: - Merge

    func testMergeCombinesEntries() throws {
        let json1 = """
        { "sourceLanguage": "en", "strings": { "Key1": {} } }
        """
        let json2 = """
        { "sourceLanguage": "en", "strings": { "Key2": {} } }
        """
        let url1 = try write(json1, name: "A.xcstrings")
        let url2 = try write(json2, name: "B.xcstrings")
        let c1 = try StringCatalogParser.parse(url: url1)
        let c2 = try StringCatalogParser.parse(url: url2)
        let merged = c1.merged(c2)
        XCTAssertEqual(merged.keys, ["Key1", "Key2"])
    }

    // MARK: - findCatalogs

    func testFindCatalogsLocatesXCStringsFiles() throws {
        let subdir = tempDir.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try write(minimalJSON, name: "Localizable.xcstrings")
        try "{}".write(to: subdir.appendingPathComponent("Other.xcstrings"), atomically: true, encoding: .utf8)

        let found = try StringCatalogParser.findCatalogs(in: tempDir)
        XCTAssertEqual(found.count, 2)
    }

    func testFindCatalogsEmptyWhenNonePresent() throws {
        let found = try StringCatalogParser.findCatalogs(in: tempDir)
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: - parseCatalogs

    func testParseCatalogsReturnsEmptyForNoFiles() throws {
        let catalog = try StringCatalogParser.parseCatalogs(in: tempDir)
        XCTAssertTrue(catalog.keys.isEmpty)
    }

    func testParseCatalogsMergesMultipleFiles() throws {
        let json1 = """
        { "sourceLanguage": "en", "strings": { "Key1": {} } }
        """
        let json2 = """
        { "sourceLanguage": "en", "strings": { "Key2": {} } }
        """
        try write(json1, name: "A.xcstrings")
        try write(json2, name: "B.xcstrings")
        let catalog = try StringCatalogParser.parseCatalogs(in: tempDir)
        XCTAssertEqual(catalog.keys, ["Key1", "Key2"])
    }

    // MARK: - empty

    func testEmptyCatalogHasNoKeys() {
        XCTAssertTrue(StringCatalog.empty.keys.isEmpty)
    }
}
