import XCTest
@testable import SwiftL10nCore

// MARK: - AssetCatalogParser tests

final class AssetCatalogParserTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetCatalogTests-\(UUID().uuidString)")
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
        let contents = #"{"images":[],"info":{"author":"xcode","version":1}}"#
        try? contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private func makeColorset(name: String, in catalog: URL) {
        let dir = catalog.appendingPathComponent("\(name).colorset")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let contents = #"{"colors":[],"info":{"author":"xcode","version":1}}"#
        try? contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private func makeGroup(name: String, in parent: URL, providesNamespace: Bool = false) -> URL {
        let dir = parent.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let contents: String
        if providesNamespace {
            contents = #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":true}}"#
        } else {
            contents = #"{"info":{"author":"xcode","version":1}}"#
        }
        try? contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        return dir
    }

    // MARK: - Basic parsing

    func testParsesImagesets() throws {
        let catalog = makeCatalog()
        makeImageset(name: "profile_icon", in: catalog)
        makeImageset(name: "logo", in: catalog)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertEqual(result.imageNames, ["profile_icon", "logo"])
        XCTAssertTrue(result.colorNames.isEmpty)
    }

    func testParsesColorsets() throws {
        let catalog = makeCatalog()
        makeColorset(name: "PrimaryBlue", in: catalog)
        makeColorset(name: "BackgroundGray", in: catalog)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertEqual(result.colorNames, ["PrimaryBlue", "BackgroundGray"])
        XCTAssertTrue(result.imageNames.isEmpty)
    }

    func testParsesMixedCatalog() throws {
        let catalog = makeCatalog()
        makeImageset(name: "banner", in: catalog)
        makeColorset(name: "Accent", in: catalog)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.contains("banner"))
        XCTAssertTrue(result.colorNames.contains("Accent"))
    }

    func testEmptyCatalogProducesNoNames() throws {
        let catalog = makeCatalog()
        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.isEmpty)
        XCTAssertTrue(result.colorNames.isEmpty)
    }

    // MARK: - AppIcon / Symbol ignored

    func testAppiconsetIsIgnored() throws {
        let catalog = makeCatalog()
        let dir = catalog.appendingPathComponent("AppIcon.appiconset")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.isEmpty, "AppIcon should not appear as a named image")
    }

    func testSymbolsetIsIgnored() throws {
        let catalog = makeCatalog()
        let dir = catalog.appendingPathComponent("custom.symbol.symbolset")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.isEmpty)
    }

    // MARK: - Groups without namespace

    func testGroupWithoutNamespaceDoesNotPrefixNames() throws {
        let catalog = makeCatalog()
        let group = makeGroup(name: "Icons", in: catalog, providesNamespace: false)
        makeImageset(name: "profile_icon", in: group)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.contains("profile_icon"),
            "Without provides-namespace, group name must NOT be prepended")
        XCTAssertFalse(result.imageNames.contains("Icons/profile_icon"))
    }

    // MARK: - Groups with namespace

    func testGroupWithNamespacePrefixesNames() throws {
        let catalog = makeCatalog()
        let group = makeGroup(name: "Icons", in: catalog, providesNamespace: true)
        makeImageset(name: "profile_icon", in: group)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.contains("Icons/profile_icon"),
            "With provides-namespace, group name must be prepended")
        XCTAssertFalse(result.imageNames.contains("profile_icon"))
    }

    func testNestedNamespaces() throws {
        let catalog = makeCatalog()
        let outer = makeGroup(name: "Outer", in: catalog, providesNamespace: true)
        let inner = makeGroup(name: "Inner", in: outer, providesNamespace: true)
        makeImageset(name: "deep_image", in: inner)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.imageNames.contains("Outer/Inner/deep_image"))
    }

    func testNamespacedGroupContainingNonNamespacedChild() throws {
        let catalog = makeCatalog()
        let outer = makeGroup(name: "Outer", in: catalog, providesNamespace: true)
        let inner = makeGroup(name: "Inner", in: outer, providesNamespace: false)
        makeImageset(name: "img", in: inner)

        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        // Outer provides namespace, Inner does not → "Outer/img"
        XCTAssertTrue(result.imageNames.contains("Outer/img"))
        XCTAssertFalse(result.imageNames.contains("Outer/Inner/img"))
    }

    // MARK: - findCatalogs

    func testFindCatalogsLocatesXcassetsBundles() {
        let project = tempDir.appendingPathComponent("MyProject")
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let cat1 = project.appendingPathComponent("Assets.xcassets")
        let cat2 = project.appendingPathComponent("BrandAssets.xcassets")
        try? FileManager.default.createDirectory(at: cat1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cat2, withIntermediateDirectories: true)

        let found = AssetCatalogParser.findCatalogs(in: project)
        let names = found.map { $0.lastPathComponent }.sorted()
        XCTAssertEqual(names, ["Assets.xcassets", "BrandAssets.xcassets"])
    }

    func testFindCatalogsDoesNotDescendIntoCatalog() {
        // An imageset inside a catalog is NOT a separate catalog
        let project = tempDir.appendingPathComponent("Proj")
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let catalog = project.appendingPathComponent("Assets.xcassets")
        try? FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        // Would look like a nested catalog if we didn't skip descendants
        let fake = catalog.appendingPathComponent("Nested.xcassets")
        try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)

        let found = AssetCatalogParser.findCatalogs(in: project)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.lastPathComponent, "Assets.xcassets")
    }

    // MARK: - AssetCatalog API

    func testContainsImageReturnsTrueForKnownAsset() throws {
        let catalog = makeCatalog()
        makeImageset(name: "splash", in: catalog)
        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.contains(image: "splash"))
        XCTAssertFalse(result.contains(image: "missing"))
    }

    func testContainsColorReturnsTrueForKnownAsset() throws {
        let catalog = makeCatalog()
        makeColorset(name: "Brand", in: catalog)
        let result = try AssetCatalogParser.parse(catalogURL: catalog)
        XCTAssertTrue(result.contains(color: "Brand"))
        XCTAssertFalse(result.contains(color: "missing"))
    }

    func testMergedCombinesImageAndColorNames() throws {
        let cat1 = makeCatalog(name: "A.xcassets")
        let cat2 = makeCatalog(name: "B.xcassets")
        makeImageset(name: "imgA", in: cat1)
        makeImageset(name: "imgB", in: cat2)
        makeColorset(name: "colorA", in: cat1)

        let merged = AssetCatalog.merged([
            try AssetCatalogParser.parse(catalogURL: cat1),
            try AssetCatalogParser.parse(catalogURL: cat2),
        ])
        XCTAssertTrue(merged.contains(image: "imgA"))
        XCTAssertTrue(merged.contains(image: "imgB"))
        XCTAssertTrue(merged.contains(color: "colorA"))
        XCTAssertEqual(merged.count, 3)
    }
}

// MARK: - AssetScanner tests

final class AssetScannerTests: XCTestCase {

    private let scanner = AssetScanner()

    // MARK: - SwiftUI Image

    func testDetectsSwiftUIImage() {
        let result = scanner.scan(source: #"Image("profile_icon")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].name, "profile_icon")
        XCTAssertEqual(result.references[0].type, .image)
        XCTAssertEqual(result.references[0].context, .swiftUIImage)
    }

    func testDetectsDecorativeImage() {
        let result = scanner.scan(source: #"Image(decorative: "banner")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].context, .swiftUIImageDecorative)
    }

    func testIgnoresSystemNameImage() {
        // Image(systemName:) uses a labeled arg — should NOT be detected as an asset ref
        let result = scanner.scan(source: #"Image(systemName: "star.fill")"#, filePath: "V.swift")
        XCTAssertTrue(result.references.isEmpty,
            "Image(systemName:) is an SF Symbol, not a catalog asset")
    }

    // MARK: - SwiftUI Color

    func testDetectsSwiftUIColor() {
        let result = scanner.scan(source: #"Color("PrimaryBlue")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].name, "PrimaryBlue")
        XCTAssertEqual(result.references[0].type, .color)
        XCTAssertEqual(result.references[0].context, .swiftUIColor)
    }

    // MARK: - UIKit

    func testDetectsUIImageNamed() {
        let result = scanner.scan(source: #"UIImage(named: "logo")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].name, "logo")
        XCTAssertEqual(result.references[0].context, .uiImageNamed)
    }

    func testDetectsUIColorNamed() {
        let result = scanner.scan(source: #"UIColor(named: "Accent")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].name, "Accent")
        XCTAssertEqual(result.references[0].context, .uiColorNamed)
    }

    // MARK: - Interpolation excluded

    func testIgnoresInterpolatedAssetNames() {
        let result = scanner.scan(source: #"Image("icon_\(size)")"#, filePath: "V.swift")
        XCTAssertTrue(result.references.isEmpty,
            "Interpolated asset names cannot be statically validated")
    }

    // MARK: - Multiple in one file

    func testDetectsMultipleReferencesInFile() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("profile_icon")
                Color("PrimaryBlue")
                Image(systemName: "star")
                UIImage(named: "logo")
            }
        }
        """
        let result = scanner.scan(source: source, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 3)

        let names = result.references.map(\.name).sorted()
        XCTAssertEqual(names, ["PrimaryBlue", "logo", "profile_icon"])
    }

    // MARK: - Fully qualified (SwiftUI.Image)

    func testDetectsFullyQualifiedImage() {
        let result = scanner.scan(source: #"SwiftUI.Image("icon")"#, filePath: "V.swift")
        XCTAssertEqual(result.references.count, 1)
        XCTAssertEqual(result.references[0].name, "icon")
    }

    // MARK: - Validation against catalog

    func testValidationPassesForKnownAsset() {
        let catalog = AssetCatalog(
            url: URL(fileURLWithPath: "Assets.xcassets"),
            imageNames: ["profile_icon"],
            colorNames: []
        )
        let result = scanner.scan(source: #"Image("profile_icon")"#, filePath: "V.swift")
        let missing = scanner.validate(result, against: catalog)
        XCTAssertTrue(missing.isEmpty)
    }

    func testValidationFlagsUnknownImage() {
        let catalog = AssetCatalog(
            url: URL(fileURLWithPath: "Assets.xcassets"),
            imageNames: [],
            colorNames: []
        )
        let result = scanner.scan(source: #"Image("missing_icon")"#, filePath: "V.swift")
        let missing = scanner.validate(result, against: catalog)
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing[0].severity, .warning)
        XCTAssertTrue(missing[0].message.contains("missing_icon"))
        XCTAssertTrue(missing[0].message.contains("Assets.xcassets"))
    }

    func testValidationFlagsUnknownColor() {
        let catalog = AssetCatalog(
            url: URL(fileURLWithPath: "Assets.xcassets"),
            imageNames: [],
            colorNames: ["KnownColor"]
        )
        let result = scanner.scan(source: #"Color("MissingColor")"#, filePath: "V.swift")
        let missing = scanner.validate(result, against: catalog)
        XCTAssertEqual(missing.count, 1)
        XCTAssertTrue(missing[0].message.contains("MissingColor"))
    }

    func testValidationOnlyFlagsMissingAssets() {
        let catalog = AssetCatalog(
            url: URL(fileURLWithPath: "Assets.xcassets"),
            imageNames: ["known_icon"],
            colorNames: []
        )
        let source = """
        Image("known_icon")
        Image("unknown_icon")
        """
        let result = scanner.scan(source: source, filePath: "V.swift")
        let missing = scanner.validate(result, against: catalog)
        XCTAssertEqual(missing.count, 1)
        XCTAssertTrue(missing[0].message.contains("unknown_icon"))
    }

    func testValidationWithNamespacedAsset() {
        let catalog = AssetCatalog(
            url: URL(fileURLWithPath: "Assets.xcassets"),
            imageNames: ["Icons/profile_icon"],
            colorNames: []
        )
        let resultHit  = scanner.scan(source: #"Image("Icons/profile_icon")"#, filePath: "V.swift")
        let resultMiss = scanner.scan(source: #"Image("profile_icon")"#, filePath: "V.swift")

        XCTAssertTrue(scanner.validate(resultHit, against: catalog).isEmpty)
        XCTAssertEqual(scanner.validate(resultMiss, against: catalog).count, 1)
    }
}
