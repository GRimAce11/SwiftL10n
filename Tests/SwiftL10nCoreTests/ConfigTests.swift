import XCTest
import Yams
@testable import SwiftL10nCore

final class ConfigTests: XCTestCase {

    // MARK: - SwiftL10nConfig defaults

    func testDefaultConfigValues() {
        let config = SwiftL10nConfig.default
        XCTAssertEqual(config.sources, ["Sources"])
        XCTAssertEqual(config.output.path, "Sources/Generated/i18n.swift")
        XCTAssertEqual(config.output.enumName, "i18n")
        XCTAssertEqual(config.output.tableName, "Localizable")
        XCTAssertEqual(config.output.mergeStrategy, .overwrite)
        XCTAssertEqual(config.minimumConfidence, 0.85)
        XCTAssertEqual(config.exclude, [])
        XCTAssertFalse(config.incremental)
        XCTAssertTrue(config.existingLocalization.patterns.isEmpty)
        XCTAssertTrue(config.existingLocalization.excludeArgumentsOf.isEmpty)
        XCTAssertFalse(config.existingLocalization.isActive)
        XCTAssertEqual(config.migration.mode, .audit)
    }

    // MARK: - YAML decoding

    func testDecodeMinimalYAML() throws {
        let yaml = """
        sources:
          - Sources
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.sources, ["Sources"])
        // Missing keys → init defaults must NOT be applied by Codable automatically
        // (they use nil-coalescing / custom init via init(from:decoder) with defaults)
    }

    func testDecodeFullYAML() throws {
        let yaml = """
        sources:
          - Sources/App
          - Sources/Shared
        output:
          path: App/Generated/i18n.swift
          enum_name: L10n
          table_name: AppStrings
        minimum_confidence: 0.75
        exclude:
          - Sources/Generated
          - "**/*.mock.swift"
        incremental: true
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.sources, ["Sources/App", "Sources/Shared"])
        XCTAssertEqual(config.output.path, "App/Generated/i18n.swift")
        XCTAssertEqual(config.output.enumName, "L10n")
        XCTAssertEqual(config.output.tableName, "AppStrings")
        XCTAssertEqual(config.minimumConfidence, 0.75, accuracy: 0.001)
        XCTAssertEqual(config.exclude, ["Sources/Generated", "**/*.mock.swift"])
        XCTAssertTrue(config.incremental)
    }

    func testDecodeSnakeCaseMinimumConfidence() throws {
        // Ensure minimum_confidence maps to minimumConfidence
        let yaml = "sources: [Sources]\nminimum_confidence: 0.6\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.minimumConfidence, 0.6, accuracy: 0.001)
    }

    func testDecodeOutputEnumNameSnakeCase() throws {
        let yaml = """
        sources: [Sources]
        output:
          path: out.swift
          enum_name: MyStrings
          table_name: Custom
        """
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.output.enumName, "MyStrings")
        XCTAssertEqual(config.output.tableName, "Custom")
    }

    func testDecodeEmptyExcludeList() throws {
        let yaml = "sources: [Sources]\nexclude: []\n"
        let config = try YAMLDecoder().decode(SwiftL10nConfig.self, from: yaml)
        XCTAssertEqual(config.exclude, [])
    }

    func testRoundTripEquality() throws {
        let original = SwiftL10nConfig(
            sources: ["Sources/App"],
            output: .init(path: "Out/i18n.swift", enumName: "L10n", tableName: "Localizable", mergeStrategy: .region),
            minimumConfidence: 0.9,
            exclude: ["Sources/Gen"],
            incremental: true,
            existingLocalization: .init(patterns: ["L10n.", "i18n."], excludeArgumentsOf: ["NSLocalizedString"]),
            migration: .init(mode: .incremental)
        )
        let encoded = try YAMLEncoder().encode(original)
        let decoded = try YAMLDecoder().decode(SwiftL10nConfig.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - ConfigLoader tests (file-system based)

final class ConfigLoaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftL10nTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Discovery

    func testDiscoverFindsConfigInStartDirectory() throws {
        let configURL = tempDir.appendingPathComponent(ConfigLoaderFileName)
        let yaml = "sources: [Sources]\n"
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)

        let found = ConfigLoaderDiscovery.discover(from: tempDir)
        XCTAssertEqual(found?.path, configURL.path)
    }

    func testDiscoverFindsConfigInParentDirectory() throws {
        let child = tempDir.appendingPathComponent("Sources/MyModule")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let configURL = tempDir.appendingPathComponent(ConfigLoaderFileName)
        let yaml = "sources: [Sources]\n"
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)

        let found = ConfigLoaderDiscovery.discover(from: child)
        XCTAssertEqual(found?.path, configURL.path)
    }

    func testDiscoverReturnsNilWhenNoConfig() {
        // tempDir has no .swiftl10n.yml — discovery should return nil before hitting $HOME
        // We need a project-root anchor to stop traversal
        let marker = tempDir.appendingPathComponent("Package.swift")
        try? "".write(to: marker, atomically: true, encoding: .utf8)

        let found = ConfigLoaderDiscovery.discover(from: tempDir)
        XCTAssertNil(found)
    }

    func testDiscoverStopsAtPackageSwift() throws {
        // Config is above Package.swift — should NOT be found
        let projectDir = tempDir.appendingPathComponent("MyProject")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Package.swift at project root (acts as stop marker)
        try "".write(to: projectDir.appendingPathComponent("Package.swift"),
                      atomically: true, encoding: .utf8)

        // Config is above the project (should be invisible)
        let yamlAbove = tempDir.appendingPathComponent(ConfigLoaderFileName)
        try "sources: [Sources]\n".write(to: yamlAbove, atomically: true, encoding: .utf8)

        let found = ConfigLoaderDiscovery.discover(from: projectDir)
        XCTAssertNil(found, "Config above Package.swift must not be discovered")
    }

    // MARK: - Loading

    func testLoadParsesYAML() throws {
        let yaml = """
        sources:
          - Sources/App
        minimum_confidence: 0.7
        incremental: true
        """
        let configURL = tempDir.appendingPathComponent(ConfigLoaderFileName)
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ConfigLoaderLoad.load(from: configURL)
        XCTAssertEqual(config.sources, ["Sources/App"])
        XCTAssertEqual(config.minimumConfidence, 0.7, accuracy: 0.001)
        XCTAssertTrue(config.incremental)
    }

    func testLoadThrowsForMissingFile() {
        let missing = tempDir.appendingPathComponent("nonexistent.yml")
        XCTAssertThrowsError(try ConfigLoaderLoad.load(from: missing)) { error in
            guard case ConfigError.fileNotFound = error else {
                XCTFail("Expected ConfigError.fileNotFound, got \(error)")
                return
            }
        }
    }

    func testLoadThrowsForInvalidYAML() throws {
        let bad = tempDir.appendingPathComponent(ConfigLoaderFileName)
        try "sources: [unclosed".write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ConfigLoaderLoad.load(from: bad)) { error in
            guard case ConfigError.parseError = error else {
                XCTFail("Expected ConfigError.parseError, got \(error)")
                return
            }
        }
    }

    // MARK: - Validation

    func testValidationPassesForExistingSource() throws {
        let sourceDir = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let config = SwiftL10nConfig(sources: ["Sources"], minimumConfidence: 0.85)
        XCTAssertNoThrow(try ConfigLoaderValidate.validate(config, relativeTo: tempDir))
    }

    func testValidationRejectsConfidenceAboveOne() {
        let config = SwiftL10nConfig(minimumConfidence: 1.5)
        XCTAssertThrowsError(try ConfigLoaderValidate.validate(config, relativeTo: tempDir)) { error in
            guard case ConfigError.validation = error else {
                XCTFail("Expected ConfigError.validation, got \(error)")
                return
            }
        }
    }

    func testValidationRejectsConfidenceBelowZero() {
        let config = SwiftL10nConfig(minimumConfidence: -0.1)
        XCTAssertThrowsError(try ConfigLoaderValidate.validate(config, relativeTo: tempDir)) { error in
            guard case ConfigError.validation = error else {
                XCTFail("Expected ConfigError.validation")
                return
            }
        }
    }

    func testValidationRejectsMissingSourcePath() {
        let config = SwiftL10nConfig(sources: ["DoesNotExist"])
        XCTAssertThrowsError(try ConfigLoaderValidate.validate(config, relativeTo: tempDir)) { error in
            guard case ConfigError.validation = error else {
                XCTFail("Expected ConfigError.validation")
                return
            }
        }
    }

    func testValidationRejectsInvalidEnumName() {
        let config = SwiftL10nConfig(output: .init(enumName: "123Invalid"))
        XCTAssertThrowsError(try ConfigLoaderValidate.validate(config, relativeTo: tempDir)) { error in
            guard case ConfigError.validation = error else {
                XCTFail("Expected ConfigError.validation for invalid enum name")
                return
            }
        }
    }

    func testValidationRejectsEnumNameWithHyphen() {
        let config = SwiftL10nConfig(output: .init(enumName: "my-enum"))
        XCTAssertThrowsError(try ConfigLoaderValidate.validate(config, relativeTo: tempDir)) { error in
            guard case ConfigError.validation = error else {
                XCTFail("Expected ConfigError.validation for hyphenated enum name")
                return
            }
        }
    }

    func testValidationAcceptsValidEnumName() {
        let config = SwiftL10nConfig(sources: [tempDir.path], output: .init(enumName: "L10n"))
        XCTAssertNoThrow(try ConfigLoaderValidate.validate(config, relativeTo: tempDir))
    }

    func testValidationAcceptsUnderscoreLeadingEnumName() {
        let config = SwiftL10nConfig(sources: [tempDir.path], output: .init(enumName: "_L10n"))
        XCTAssertNoThrow(try ConfigLoaderValidate.validate(config, relativeTo: tempDir))
    }
}

// MARK: - Test-only shims
// ConfigLoader and ConfigError live in the `swiftl10n` executable target which
// cannot be imported in tests. These shims duplicate the pure logic so tests
// can exercise it without coupling to the CLI target.

private let ConfigLoaderFileName = ".swiftl10n.yml"

private enum ConfigLoaderDiscovery {
    private static let rootAnchors = ["Package.swift", ".git", ".xcworkspace", ".xcodeproj"]

    static func discover(from startURL: URL) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var current = startURL.standardized
        while true {
            let candidate = current.appendingPathComponent(ConfigLoaderFileName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            for anchor in rootAnchors
            where FileManager.default.fileExists(atPath: current.appendingPathComponent(anchor).path) {
                return nil
            }
            if current.standardized.path == home.standardized.path { return nil }
            let parent = current.deletingLastPathComponent()
            if parent.standardized.path == current.standardized.path { return nil }
            current = parent
        }
    }
}

private enum ConfigLoaderLoad {
    static func load(from url: URL) throws -> SwiftL10nConfig {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw ConfigError.fileNotFound(url) }
        do { return try YAMLDecoder().decode(SwiftL10nConfig.self, from: text) }
        catch { throw ConfigError.parseError(error.localizedDescription) }
    }
}

private enum ConfigLoaderValidate {
    static func validate(_ config: SwiftL10nConfig, relativeTo base: URL) throws {
        guard config.minimumConfidence >= 0.0, config.minimumConfidence <= 1.0 else {
            throw ConfigError.validation("minimum_confidence out of range: \(config.minimumConfidence)")
        }
        guard isValidIdentifier(config.output.enumName) else {
            throw ConfigError.validation("output.enum_name '\(config.output.enumName)' is not a valid Swift identifier")
        }
        guard isValidIdentifier(config.assets.enumName) else {
            throw ConfigError.validation("assets.enum_name '\(config.assets.enumName)' is not a valid Swift identifier")
        }
        for source in config.sources {
            let resolved = source.hasPrefix("/")
                ? URL(fileURLWithPath: source)
                : base.appendingPathComponent(source)
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw ConfigError.validation("Source path does not exist: \(source)")
            }
        }
    }

    static func isValidIdentifier(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let first = name.unicodeScalars.first!
        guard CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else { return false }
        return name.unicodeScalars.dropFirst().allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
        }
    }
}

private enum ConfigError: Error {
    case fileNotFound(URL)
    case parseError(String)
    case validation(String)
}
