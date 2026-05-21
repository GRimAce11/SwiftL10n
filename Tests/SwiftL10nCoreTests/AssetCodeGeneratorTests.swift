import XCTest
import Yams
@testable import SwiftL10nCore

final class AssetCodeGeneratorTests: XCTestCase {

    private let gen = AssetCodeGenerator()

    // MARK: - Identifier conversion

    func testSnakeCaseToIdentifier() {
        XCTAssertEqual(gen.swiftIdentifier(from: "profile_icon"), "profileIcon")
    }

    func testKebabCaseToIdentifier() {
        XCTAssertEqual(gen.swiftIdentifier(from: "app-icon"), "appIcon")
    }

    func testPascalCaseToIdentifier() {
        // First character lowercased, rest preserved
        XCTAssertEqual(gen.swiftIdentifier(from: "PrimaryBlue"), "primaryBlue")
    }

    func testCamelCasePreserved() {
        XCTAssertEqual(gen.swiftIdentifier(from: "myButton"), "myButton")
    }

    func testAllLowerPreserved() {
        XCTAssertEqual(gen.swiftIdentifier(from: "logo"), "logo")
    }

    func testDigitPrefixGetsUnderscore() {
        XCTAssertTrue(gen.swiftIdentifier(from: "2x_icon").hasPrefix("_"))
    }

    func testDotSeparatedToIdentifier() {
        XCTAssertEqual(gen.swiftIdentifier(from: "my.icon"), "myIcon")
    }

    // MARK: - Type name conversion

    func testTypeNamePascalCasedFromSnake() {
        XCTAssertEqual(gen.swiftTypeName(from: "my_icons"), "MyIcons")
    }

    func testTypeNamePreservedIfAlreadyPascal() {
        XCTAssertEqual(gen.swiftTypeName(from: "Icons"), "Icons")
    }

    func testTypeNameFromKebab() {
        XCTAssertEqual(gen.swiftTypeName(from: "brand-assets"), "BrandAssets")
    }

    // MARK: - Empty catalog

    func testEmptyCatalogGeneratesEmptyEnum() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: [], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("public enum Assets {"))
        XCTAssertTrue(output.contains("No assets found"))
    }

    // MARK: - Images only

    func testRootLevelImageGeneratesFunc() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["logo"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("public static func logo() -> Image"))
        XCTAssertTrue(output.contains("Image(\"logo\")"))
    }

    func testSnakeCaseImageIdentifier() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["profile_icon"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("func profileIcon()"))
        XCTAssertTrue(output.contains("Image(\"profile_icon\")"))
    }

    // MARK: - Colors only

    func testColorGeneratesCorrectReturnType() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: [], colorNames: ["PrimaryBlue"])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("func primaryBlue() -> Color"))
        XCTAssertTrue(output.contains("Color(\"PrimaryBlue\")"))
    }

    // MARK: - Mixed images and colors

    func testMixedCatalogHasBothMarks() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["logo"], colorNames: ["Accent"])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("// MARK: - Images"))
        XCTAssertTrue(output.contains("// MARK: - Colors"))
        XCTAssertTrue(output.contains("func logo()"))
        XCTAssertTrue(output.contains("func accent()"))
    }

    // MARK: - Namespace-aware generation

    func testNamespacedImageGeneratesExtension() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["Icons/profile_icon"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("extension Assets {"))
        XCTAssertTrue(output.contains("public enum Icons {"))
        XCTAssertTrue(output.contains("func profileIcon()"))
        XCTAssertTrue(output.contains("Image(\"Icons/profile_icon\")"))
    }

    func testNamespacedColorFullPath() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: [], colorNames: ["Theme/Accent"])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("Color(\"Theme/Accent\")"))
    }

    func testRootAndNamespacedAssetsCoexist() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["logo", "Icons/profile_icon"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        // Root enum has logo
        XCTAssertTrue(output.contains("public enum Assets {"))
        XCTAssertTrue(output.contains("func logo()"))
        // Extension has Icons namespace
        XCTAssertTrue(output.contains("extension Assets {"))
        XCTAssertTrue(output.contains("public enum Icons {"))
        XCTAssertTrue(output.contains("func profileIcon()"))
    }

    func testDeepNamespace() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["Outer/Inner/deep_img"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("enum Outer"))
        XCTAssertTrue(output.contains("enum Inner"))
        XCTAssertTrue(output.contains("func deepImg()"))
        XCTAssertTrue(output.contains("Image(\"Outer/Inner/deep_img\")"))
    }

    // MARK: - Collision handling

    func testCollisionInSameNamespaceSuffixed() {
        // "icon_a" and "icon_A" both normalize to "iconA" — collision
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["icon_a", "icon_A"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("func iconA()"))
        XCTAssertTrue(output.contains("func iconA_2()"),
            "Second entry with same identifier must get _2 suffix")
    }

    // MARK: - Configuration

    func testCustomRootEnumName() {
        let config = AssetCodeGenerator.Configuration(rootEnumName: "R")
        let output = AssetCodeGenerator(configuration: config)
            .generate(catalog: AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                            imageNames: ["logo"], colorNames: []))
        XCTAssertTrue(output.contains("public enum R {"))
        XCTAssertFalse(output.contains("public enum Assets {"))
    }

    func testInternalAccessLevel() {
        let config = AssetCodeGenerator.Configuration(accessLevel: "internal")
        let output = AssetCodeGenerator(configuration: config)
            .generate(catalog: AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                            imageNames: ["logo"], colorNames: []))
        XCTAssertTrue(output.contains("internal enum Assets {"))
        XCTAssertTrue(output.contains("internal static func logo()"))
        XCTAssertFalse(output.contains("public"))
    }

    // MARK: - Determinism

    func testOutputIsDeterministic() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["c_img", "a_img", "b_img"],
                                   colorNames: ["ZColor", "AColor"])
        let out1 = gen.generate(catalog: catalog)
        let out2 = gen.generate(catalog: catalog)
        XCTAssertEqual(out1, out2, "Same catalog must always produce identical output")
    }

    func testImagesAreSortedAlphabetically() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["zebra", "alpha", "middle"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        let alphaRange  = output.range(of: "func alpha()")!
        let middleRange = output.range(of: "func middle()")!
        let zebraRange  = output.range(of: "func zebra()")!
        XCTAssertTrue(alphaRange.lowerBound < middleRange.lowerBound
                   && middleRange.lowerBound < zebraRange.lowerBound,
            "Assets should be emitted in sorted order")
    }

    // MARK: - File structure

    func testHeaderIsPresent() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["logo"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.hasPrefix("// Auto-generated by SwiftL10n"))
        XCTAssertTrue(output.contains("import SwiftUI"))
    }

    func testDocCommentContainsFullAssetName() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "A.xcassets"),
                                   imageNames: ["Icons/profile_icon"], colorNames: [])
        let output = gen.generate(catalog: catalog)
        XCTAssertTrue(output.contains("/// Asset: \"Icons/profile_icon\""))
    }
}

// MARK: - AssetsOutputConfig tests

final class AssetsOutputConfigTests: XCTestCase {

    func testDefaultValues() {
        let config = SwiftL10nConfig.AssetsOutputConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.path, "Sources/Generated/Assets.swift")
        XCTAssertEqual(config.enumName, "Assets")
    }

    func testAssetsNotEnabledByDefaultInMainConfig() {
        XCTAssertFalse(SwiftL10nConfig.default.assets.enabled)
    }

    func testDecodeAssetsSection() throws {
        let yaml = """
        sources: [Sources]
        assets:
          enabled: true
          path: App/Generated/Assets.swift
          enum_name: R
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertTrue(config.assets.enabled)
        XCTAssertEqual(config.assets.path, "App/Generated/Assets.swift")
        XCTAssertEqual(config.assets.enumName, "R")
    }

    func testAssetsSectionDefaultsWhenOmitted() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertFalse(config.assets.enabled)
        XCTAssertEqual(config.assets.enumName, "Assets")
    }
}
