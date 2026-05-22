import XCTest
import Yams
@testable import SwiftL10nCore

final class ImageResourceTests: XCTestCase {

    // MARK: - Config decoding

    func testDefaultUseImageResourceIsFalse() throws {
        let yaml = "sources: [Sources]\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertFalse(config.assets.useImageResource)
    }

    func testDecodeUseImageResourceTrue() throws {
        let yaml = """
        sources: [Sources]
        assets:
          enabled: true
          use_image_resource: true
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertTrue(config.assets.useImageResource)
    }

    // MARK: - AssetCodeGenerator output

    func testDefaultGeneratesImageFunc() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "Test.xcassets"), imageNames: ["logo"], colorNames: [])
        let code = AssetCodeGenerator(configuration: .init()).generate(catalog: catalog)
        XCTAssertTrue(code.contains("static func logo() -> Image"), "Default output must use Image func")
        XCTAssertFalse(code.contains("ImageResource"), "Default output must not use ImageResource")
    }

    func testImageResourceGeneratesVarWithAvailability() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "Test.xcassets"), imageNames: ["logo", "Icons/profile"], colorNames: [])
        let config  = AssetCodeGenerator.Configuration(useImageResource: true)
        let code    = AssetCodeGenerator(configuration: config).generate(catalog: catalog)

        XCTAssertTrue(code.contains("@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)"),
                      "ImageResource accessors must have @available annotation")
        XCTAssertTrue(code.contains("static var logo: ImageResource"),
                      "Must generate static var returning ImageResource")
        XCTAssertTrue(code.contains("ImageResource(name: \"logo\", bundle: .main)"),
                      "Must use ImageResource(name:bundle:) initializer")
        XCTAssertFalse(code.contains("-> Image"),
                       "ImageResource mode must not generate Image return type")
    }

    func testImageResourceDoesNotAffectColors() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "Test.xcassets"), imageNames: ["logo"], colorNames: ["primaryBlue"])
        let config  = AssetCodeGenerator.Configuration(useImageResource: true)
        let code    = AssetCodeGenerator(configuration: config).generate(catalog: catalog)

        XCTAssertTrue(code.contains("static func primaryBlue() -> Color"),
                      "Colors must always use Color func, not ImageResource")
    }

    func testImageResourceWithNamespace() {
        let catalog = AssetCatalog(url: URL(fileURLWithPath: "Test.xcassets"), imageNames: ["Icons/profileIcon"], colorNames: [])
        let config  = AssetCodeGenerator.Configuration(useImageResource: true)
        let code    = AssetCodeGenerator(configuration: config).generate(catalog: catalog)

        XCTAssertTrue(code.contains("ImageResource(name: \"Icons/profileIcon\", bundle: .main)"),
                      "Namespaced asset must use full catalog path in ImageResource")
        XCTAssertTrue(code.contains("@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)"))
    }

    func testImageResourceConfigPreservedInRoundTrip() throws {
        let original = SwiftL10nConfig(
            assets: .init(enabled: true, path: "Gen/Assets.swift", enumName: "Assets", useImageResource: true)
        )
        let encoded = try YAMLEncoder().encode(original)
        let decoded = try YAMLDecoder().decode(SwiftL10nConfig.self, from: encoded)
        XCTAssertEqual(original.assets, decoded.assets)
        XCTAssertTrue(decoded.assets.useImageResource)
    }
}
