import Foundation

// MARK: - Top-level convenience function

/// Discovers every `.xcassets` catalog near `sourcesPath`, generates a typed
/// `enum Assets { … }` scaffold, and writes it to `outputPath` — all in one call.
///
/// Call it alongside `generateStrings()` from any SwiftUI view or AppDelegate:
///
/// ```swift
/// let projectPath = "/Users/you/Developer/YourApp/Sources/YourApp"
///
/// try? await generateStrings(
///     sourcesPath: projectPath,
///     outputPath:  "\(projectPath)/Generated/i18n.swift"
/// )
/// try? await generateAssets(
///     sourcesPath: projectPath,
///     outputPath:  "\(projectPath)/Generated/Assets.swift"
/// )
/// ```
///
/// Catalog discovery walks up to three directory levels from `sourcesPath`,
/// covering the most common Xcode and SPM project layouts.
///
/// - Parameters:
///   - sourcesPath: A directory SwiftL10n uses as the starting point for catalog discovery.
///                  This is typically the same path you pass to `generateStrings()`.
///   - outputPath:  Where `Assets.swift` will be written. The parent directory is created
///                  automatically if it does not exist.
///   - enumName:    Root enum name in the generated file. Default `Assets`.
/// - Returns: Summary — number of catalogs found, image count, color count, and output URL.
@discardableResult
public func generateAssets(
    sourcesPath: String,
    outputPath: String,
    enumName: String = "Assets"
) async throws -> AssetsGenerator.Result {
    try await AssetsGenerator(
        sourcesPath: sourcesPath,
        outputPath: outputPath,
        enumName: enumName
    ).run()
}

// MARK: -

/// Discovers `.xcassets` catalogs near a source directory and writes a type-safe
/// `Assets.swift` file from their contents.
///
/// Generation source is the **parsed catalog**, not detected source references —
/// every asset declared in the catalog gets a typed accessor, whether or not your
/// code already references it.
///
/// ```swift
/// let result = try await AssetsGenerator(
///     sourcesPath: "/path/to/Sources/YourApp",
///     outputPath:  "/path/to/Sources/YourApp/Generated/Assets.swift"
/// ).run()
/// print("\(result.imageCount) image(s), \(result.colorCount) color(s)")
/// ```
public struct AssetsGenerator: Sendable {

    // MARK: - Result

    public struct Result: Sendable {
        /// Number of `.xcassets` catalogs found and merged.
        public let catalogCount: Int
        /// Number of image assets across all catalogs.
        public let imageCount: Int
        /// Number of color assets across all catalogs.
        public let colorCount: Int
        /// File URL of the written `Assets.swift`.
        public let outputURL: URL
    }

    // MARK: - Configuration

    private let sourcesURL: URL
    private let outputURL: URL
    private let enumName: String

    // MARK: - Init

    public init(
        sourcesPath: String,
        outputPath: String,
        enumName: String = "Assets"
    ) {
        self.sourcesURL = URL(fileURLWithPath: sourcesPath)
        self.outputURL  = URL(fileURLWithPath: outputPath)
        self.enumName   = enumName
    }

    // MARK: - Run

    public func run() async throws -> Result {
        let copy = self
        return try await Task.detached(priority: .userInitiated) {
            try copy.execute()
        }.value
    }

    // MARK: - Private

    private func execute() throws -> Result {
        // Discover catalogs
        let catalogURLs = discoverCatalogURLs(from: sourcesURL)
        let catalogs    = catalogURLs.compactMap { try? AssetCatalogParser.parse(catalogURL: $0) }
        let merged      = AssetCatalog.merged(catalogs)

        // Generate
        let genConfig = AssetCodeGenerator.Configuration(rootEnumName: enumName)
        let code      = AssetCodeGenerator(configuration: genConfig).generate(catalog: merged)

        // Console report
        if catalogs.isEmpty {
            print("── Asset generation: no .xcassets catalogs found near \(sourcesURL.lastPathComponent)")
        } else {
            let names = catalogURLs.map(\.lastPathComponent).joined(separator: ", ")
            print("── Asset generation (\(names))")
            print("   \(merged.imageNames.count) image(s) · \(merged.colorNames.count) color(s)")
        }

        let writtenURL = try writeGeneratedFile(code, to: outputURL)

        return Result(
            catalogCount: catalogs.count,
            imageCount:   merged.imageNames.count,
            colorCount:   merged.colorNames.count,
            outputURL:    writtenURL
        )
    }

    // MARK: - Catalog discovery

    /// Walk up to 3 levels from `startURL`, collecting every `.xcassets` bundle found.
    /// Uses a **shallow** search at each level — only immediate children of each directory
    /// are checked, not the full subtree. This avoids picking up unrelated catalogs from
    /// sibling directories while still finding the common project layouts:
    ///   Sources/YourApp/Assets.xcassets    (level 0)
    ///   Sources/Assets.xcassets            (level 1)
    ///   YourApp/Assets.xcassets            (level 2)
    private func discoverCatalogURLs(from startURL: URL) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var search = startURL
        var found: [URL] = []

        for _ in 0..<3 {
            if let items = try? FileManager.default.contentsOfDirectory(
                at: search,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for item in items where item.pathExtension == "xcassets" {
                    found.append(item)
                }
            }
            if search.resolvingSymlinksInPath().path == home.resolvingSymlinksInPath().path { break }
            let parent = search.deletingLastPathComponent()
            if parent.path == search.path { break }
            search = parent
        }
        return found
    }
}
