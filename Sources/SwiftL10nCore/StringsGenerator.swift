import Foundation

// MARK: - Top-level convenience function

/// Scans every `.swift` file under `sourcesPath`, generates the `enum i18n { … }` scaffold,
/// writes it to `outputPath`, and validates all `Image("…")` / `Color("…")` / `UIImage(named:)`
/// calls against any `.xcassets` catalogs found near `sourcesPath`.
///
/// All of this happens in a single call — no extra setup required:
///
/// ```swift
/// .task {
///     let projectPath = "/path/to/Sources/MyApp"   // ← change only this
///     try? await generateStrings(
///         sourcesPath: projectPath,
///         outputPath:  "\(projectPath)/Generated/i18n.swift"
///     )
/// }
/// ```
///
/// - Parameters:
///   - sourcesPath: Folder containing your `.swift` view files (scanned recursively).
///   - outputPath:  Where `i18n.swift` will be written. Parent folder is created if needed.
///   - minimumConfidence: Ignore strings below this score. Default `0.85`.
/// - Returns: Summary — string count, namespace count, warning count, missing asset count, output URL.
@discardableResult
public func generateStrings(
    sourcesPath: String,
    outputPath: String,
    minimumConfidence: Double = 0.85
) async throws -> StringsGenerator.Result {
    try await StringsGenerator(
        sourcesPath: sourcesPath,
        outputPath: outputPath,
        minimumConfidence: minimumConfidence
    ).run()
}

// MARK: -

/// Scans a source directory, validates asset references, and writes a `i18n.swift` enum in one call.
///
/// - Localization: detects every hardcoded SwiftUI/UIKit string, infers namespaces, generates `i18n.swift`.
/// - Asset validation: discovers `.xcassets` catalogs near `sourcesPath`, cross-references every
///   `Image("…")`, `Color("…")`, `UIImage(named:)`, and `UIColor(named:)` call, and prints a warning
///   for each name absent from the catalog. No separate setup needed.
///
/// ```swift
/// let result = try await StringsGenerator(
///     sourcesPath: "/path/to/Sources/MyApp",
///     outputPath:  "/path/to/Sources/MyApp/Generated/i18n.swift"
/// ).run()
/// print("\(result.missingAssetCount) missing asset(s)")
/// ```
public struct StringsGenerator: Sendable {

    // MARK: - Result

    public struct Result: Sendable {
        /// Total number of localizable strings found across all files.
        public let stringCount: Int
        /// Number of namespace groups inferred from file names.
        public let namespaceCount: Int
        /// Number of interpolated strings that need manual attention.
        public let warningCount: Int
        /// Number of asset references (`Image("…")` etc.) not found in any `.xcassets` catalog.
        /// `0` when no catalogs are present (no validation is attempted).
        public let missingAssetCount: Int
        /// File URL of the written `i18n.swift`.
        public let outputURL: URL
    }

    // MARK: - Errors

    public enum GeneratorError: Error, LocalizedError {
        case sourceDirectoryNotFound(String)
        case permissionDenied(String)

        public var errorDescription: String? {
            switch self {
            case .sourceDirectoryNotFound(let path):
                return "Source directory not found at: \(path)"
            case .permissionDenied(let path):
                return """
                Permission denied — cannot write to: \(path)

                This is caused by the App Sandbox. Fix it with one of these options:

                Option 1 (recommended for dev tools):
                  Xcode → Your Target → Signing & Capabilities
                  → App Sandbox → uncheck "Enable App Sandbox"

                Option 2 (keep sandbox, grant file access):
                  Xcode → Your Target → Signing & Capabilities
                  → App Sandbox → File Access → User Selected Files → Read/Write

                Option 3 (safest — wrap the call so it never runs in production):
                  #if DEBUG
                  Task { await scanStrings() }
                  #endif
                """
            }
        }
    }

    // MARK: - Configuration

    private let sourcesURL: URL
    private let outputURL: URL
    private let minimumConfidence: Double
    private let ruleEngine: RuleEngine

    // MARK: - Init

    /// - Parameters:
    ///   - sourcesPath: Absolute path to the folder containing your `.swift` view files.
    ///   - outputPath:  Absolute path where `i18n.swift` will be written.
    ///                  The parent directory is created automatically if it does not exist.
    ///   - minimumConfidence: Strings below this threshold are ignored. Default `0.85`.
    public init(
        sourcesPath: String,
        outputPath: String,
        minimumConfidence: Double = 0.85,
        ruleEngine: RuleEngine = .default
    ) {
        self.sourcesURL = URL(fileURLWithPath: sourcesPath)
        self.outputURL  = URL(fileURLWithPath: outputPath)
        self.minimumConfidence = minimumConfidence
        self.ruleEngine = ruleEngine
    }

    // MARK: - Run

    /// Scan, validate assets, generate, and write. Runs on a background thread.
    public func run() async throws -> Result {
        let copy = self
        return try await Task.detached(priority: .userInitiated) {
            try copy.execute()
        }.value
    }

    // MARK: - Private

    private func execute() throws -> Result {
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw GeneratorError.sourceDirectoryNotFound(sourcesURL.path)
        }

        // ── Discover asset catalogs near sourcesURL ────────────────────────
        let catalog = discoverCatalog(from: sourcesURL)
        let assetScanner: AssetScanner? = catalog.count > 0 ? AssetScanner() : nil

        // ── Scan files ────────────────────────────────────────────────────
        let locScanner = StringScanner(ruleEngine: ruleEngine, minimumConfidence: minimumConfidence)
        var fileResults: [(String, [DetectedString])] = []
        var warningCount = 0
        var missingAssets: [Diagnostic] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)

            // Localization scan
            let locResult = locScanner.scan(source: source, filePath: url.lastPathComponent)
            warningCount += locResult.diagnostics.filter { $0.severity == .warning }.count
            guard !locResult.detectedStrings.isEmpty else { continue }

            print("── \(url.lastPathComponent) (\(locResult.detectedStrings.count) string(s))")
            for s in locResult.detectedStrings {
                let pct  = String(format: "%.0f%%", s.confidence * 100)
                let flag = s.hasInterpolation ? "  ⚠ interpolated — skipped in codegen" : ""
                print("   [\(s.context.displayName)] \"\(s.value)\"  \(pct)\(flag)")
            }

            fileResults.append((url.lastPathComponent, locResult.detectedStrings))

            // Asset validation (same source, no extra file I/O)
            if let assetScanner {
                let assetResult = assetScanner.scan(source: source, filePath: url.lastPathComponent)
                missingAssets.append(contentsOf: assetScanner.validate(assetResult, against: catalog))
            }
        }

        // ── Asset validation report ───────────────────────────────────────
        if catalog.count > 0 {
            let catalogNames = assetCatalogNames(from: sourcesURL)
            let header = catalogNames.isEmpty
                ? "Asset validation (\(catalog.count) asset(s))"
                : "Asset validation (\(catalog.count) asset(s) · \(catalogNames.joined(separator: ", ")))"

            if missingAssets.isEmpty {
                print("\n── \(header)")
                print("   ✓ All asset references resolved")
            } else {
                print("\n── \(header)")
                for d in missingAssets {
                    let loc = d.location.map { "  [\($0.file):\($0.line)]" } ?? ""
                    print("   ⚠ \(d.message)\(loc)")
                }
            }
        }

        // ── Namespace inference + common extraction + codegen ─────────────
        let namespaces = NamespaceInferrer().infer(from: fileResults)
        let extraction = CommonStringExtractor().extract(from: namespaces)

        var allNamespaces = extraction.namespaces
        if let common = extraction.common, !common.strings.isEmpty {
            print("\n── Common strings (shared across multiple files → i18n.Common)")
            for s in common.strings {
                let from = extraction.origins[s.value]?.joined(separator: ", ") ?? ""
                print("   \"\(s.value)\"  ← \(from)")
            }
            allNamespaces.insert(common, at: 0)
        }

        let code = CodeGenerator().generate(namespaces: allNamespaces)

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let existed = FileManager.default.fileExists(atPath: outputURL.path)
            try code.write(to: outputURL, atomically: true, encoding: .utf8)
            let action = existed ? "Updated" : "Created"
            print("\n✓ \(action) → \(outputURL.path)")
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
               && [NSFileWriteNoPermissionError,
                   NSFileReadNoPermissionError].contains(error.code) {
            throw GeneratorError.permissionDenied(outputURL.path)
        }

        let totalStrings = fileResults.flatMap(\.1).count
        print("✓ \(totalStrings) string(s) · \(allNamespaces.count) namespace(s) · \(warningCount) warning(s) · \(missingAssets.count) missing asset(s)")

        return Result(
            stringCount:       totalStrings,
            namespaceCount:    allNamespaces.count,
            warningCount:      warningCount,
            missingAssetCount: missingAssets.count,
            outputURL:         outputURL
        )
    }

    // MARK: - Asset catalog discovery

    /// Walk up from `startURL` (up to 3 levels) collecting all `.xcassets` bundles,
    /// parse them, and return a merged catalog. Returns an empty catalog if none found.
    ///
    /// Covers the most common Xcode/SPM project layouts:
    ///   Sources/YourApp/Assets.xcassets       (level 0)
    ///   Sources/Assets.xcassets               (level 1)
    ///   YourApp/Assets.xcassets               (level 2, standard Xcode project)
    private func discoverCatalog(from startURL: URL) -> AssetCatalog {
        let urls = shallowCatalogURLs(from: startURL)
        let parsed = urls.compactMap { try? AssetCatalogParser.parse(catalogURL: $0) }
        return AssetCatalog.merged(parsed)
    }

    private func assetCatalogNames(from startURL: URL) -> [String] {
        shallowCatalogURLs(from: startURL).map(\.lastPathComponent)
    }

    /// Shallow walk up to 3 levels: only immediate children of each directory are checked.
    /// Avoids picking up unrelated catalogs from sibling directories.
    private func shallowCatalogURLs(from startURL: URL) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
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
