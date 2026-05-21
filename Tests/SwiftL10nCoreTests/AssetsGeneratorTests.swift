import XCTest
@testable import SwiftL10nCore

final class AssetsGeneratorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetsGeneratorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCatalog(name: String = "Assets.xcassets") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImageset(name: String, in catalog: URL) {
        let dir = catalog.appendingPathComponent("\(name).imageset")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func makeColorset(name: String, in catalog: URL) {
        let dir = catalog.appendingPathComponent("\(name).colorset")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Tests

    func testGeneratesAssetsSwiftFromCatalog() async throws {
        let catalog = makeCatalog()
        makeImageset(name: "logo", in: catalog)
        makeColorset(name: "Accent", in: catalog)

        let outputPath = tempDir.appendingPathComponent("Assets.swift").path

        let result = try await generateAssets(
            sourcesPath: tempDir.path,
            outputPath: outputPath
        )

        XCTAssertEqual(result.catalogCount, 1)
        XCTAssertEqual(result.imageCount, 1)
        XCTAssertEqual(result.colorCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))

        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content.contains("func logo()"))
        XCTAssertTrue(content.contains("func accent()"))
    }

    func testGeneratesEmptyFileWhenNoCatalogsFound() async throws {
        let outputPath = tempDir.appendingPathComponent("Assets.swift").path

        let result = try await generateAssets(
            sourcesPath: tempDir.path,
            outputPath: outputPath
        )

        XCTAssertEqual(result.catalogCount, 0)
        XCTAssertEqual(result.imageCount, 0)
        XCTAssertEqual(result.colorCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }

    func testCustomEnumName() async throws {
        let catalog = makeCatalog()
        makeImageset(name: "icon", in: catalog)

        let outputPath = tempDir.appendingPathComponent("R.swift").path

        _ = try await generateAssets(
            sourcesPath: tempDir.path,
            outputPath: outputPath,
            enumName: "R"
        )

        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content.contains("public enum R {"))
    }

    func testDiscoversCatalogInParentDirectory() async throws {
        // Catalog is at tempDir/Assets.xcassets
        // sourcesPath is tempDir/Sources — one level deeper
        let catalog = makeCatalog()
        makeImageset(name: "logo", in: catalog)

        let sourcesDir = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let outputPath = tempDir.appendingPathComponent("Assets.swift").path

        let result = try await generateAssets(
            sourcesPath: sourcesDir.path,
            outputPath: outputPath
        )

        XCTAssertEqual(result.catalogCount, 1, "Catalog in parent directory must be discovered")
        XCTAssertEqual(result.imageCount, 1)
    }

    func testCreatesOutputDirectoryIfNeeded() async throws {
        let catalog = makeCatalog()
        makeImageset(name: "logo", in: catalog)

        let nestedOutput = tempDir
            .appendingPathComponent("Generated/Assets.swift").path

        _ = try await generateAssets(
            sourcesPath: tempDir.path,
            outputPath: nestedOutput
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedOutput))
    }

    func testResultURLMatchesOutputPath() async throws {
        let outputPath = tempDir.appendingPathComponent("Assets.swift").path

        let result = try await generateAssets(
            sourcesPath: tempDir.path,
            outputPath: outputPath
        )

        XCTAssertEqual(result.outputURL.path, outputPath)
    }
}
