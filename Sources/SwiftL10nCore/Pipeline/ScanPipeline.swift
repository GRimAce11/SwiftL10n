import Foundation

/// Orchestrates the full scan pipeline: file collection → pre-pass → scanning → namespace inference.
///
/// `ScanPipeline` is the reusable core extracted from `ScanCommand`. It owns no I/O
/// state and is safe to call multiple times.
///
/// ```swift
/// let pipeline = ScanPipeline(config: config, baseURL: projectRoot)
/// let result = try pipeline.run()
/// ```
public struct ScanPipeline: Sendable {

    // MARK: - Result

    public struct PipelineResult: Sendable {
        /// Number of `.swift` files that were opened and scanned.
        public let scannedFiles: Int
        /// Inferred namespaces — one per source file that had detectable strings.
        public let namespaces: [Namespace]
        /// All diagnostics emitted during this run (notes, warnings, errors).
        public let diagnostics: [Diagnostic]
        /// Files served from the incremental cache without re-scanning.
        public let cacheHits: Int
        /// Total existing localization call sites recognized (across all patterns).
        public let existingLocalizationCount: Int
        /// String literals suppressed because they appeared inside excluded functions.
        public let suppressedStringCount: Int
        /// Migration mode used for this run.
        public let migrationMode: SwiftL10nConfig.MigrationConfig.Mode

        /// Sum of strings across all namespaces.
        public var totalStrings: Int { namespaces.reduce(0) { $0 + $1.strings.count } }

        public var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }
        public var errorCount: Int   { diagnostics.filter { $0.severity == .error   }.count }
    }

    // MARK: - Configuration

    /// Project-level config (sources, exclusions, confidence, etc.).
    public let config: SwiftL10nConfig
    /// Directory that relative paths in `config` are resolved against —
    /// usually the directory containing `.swiftl10n.yml`, or the cwd.
    public let baseURL: URL

    public init(config: SwiftL10nConfig, baseURL: URL) {
        self.config  = config
        self.baseURL = baseURL
    }

    // MARK: - Run

    /// Collect files, run pre-pass, scan, and infer namespaces.
    ///
    /// - Parameters:
    ///   - sources: Override `config.sources`. `nil` uses config values.
    ///   - minimumConfidence: Override `config.minimumConfidence`. `nil` uses config value.
    ///   - migrationMode: Override `config.migration.mode`. `nil` uses config value.
    public func run(
        sources: [String]? = nil,
        minimumConfidence: Double? = nil,
        migrationMode: SwiftL10nConfig.MigrationConfig.Mode? = nil
    ) throws -> PipelineResult {
        let effectiveSources    = sources ?? config.sources
        let effectiveConfidence = minimumConfidence ?? config.minimumConfidence
        let effectiveMode       = migrationMode ?? config.migration.mode

        // Pre-pass is active when patterns are configured OR mode is incremental/strict.
        let prePasActive = config.existingLocalization.isActive
            || effectiveMode == .incremental
            || effectiveMode == .strict

        let detector = prePasActive
            ? ExistingLocalizationDetector(config: config.existingLocalization.detectorConfig)
            : nil

        let scanner = StringScanner(minimumConfidence: effectiveConfidence)
        let engine  = DiagnosticsEngine()
        var fileResults: [(filePath: String, strings: [DetectedString])] = []
        var scannedFileCount          = 0
        var cacheHits                 = 0
        var existingLocalizationCount = 0
        var suppressedStringCount     = 0

        // Load incremental cache (no-op when incremental is disabled)
        let cacheURL = baseURL.appendingPathComponent(ScanCache.defaultRelativePath)
        var cache: ScanCache = config.incremental
            ? ((try? IncrementalScanCache.load(from: cacheURL)) ?? ScanCache())
            : ScanCache()
        var cacheModified = false

        for source in effectiveSources {
            let sourceURL = resolvedURL(for: source)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
                engine.emit(.error, "Source path not found: \(source)")
                continue
            }

            let files: [URL] = isDir.boolValue
                ? collectSwiftFiles(in: sourceURL)
                : sourceURL.pathExtension == "swift" ? [sourceURL] : []

            scannedFileCount += files.count

            for fileURL in files {
                let cacheKey = fileURL.resolvingSymlinksInPath().path

                // Incremental: serve from cache if content unchanged
                if config.incremental,
                   let hash = try? IncrementalScanCache.contentHash(of: fileURL),
                   cache.isValid(for: cacheKey, hash: hash),
                   let entry = cache.entries[cacheKey] {
                    entry.diagnostics.forEach { engine.emit($0) }
                    if !entry.detectedStrings.isEmpty {
                        fileResults.append((filePath: fileURL.path, strings: entry.detectedStrings))
                    }
                    existingLocalizationCount += entry.existingLocalizationDetections.count
                    cacheHits += 1
                    continue
                }

                // Full scan
                do {
                    let source = try String(contentsOf: fileURL, encoding: .utf8)

                    // Phase A: existing localization pre-pass
                    var prePasResult = ExistingLocalizationDetector.Result.empty
                    if let detector {
                        prePasResult = detector.detect(source: source, filePath: fileURL.path)
                        existingLocalizationCount += prePasResult.detections.count
                    }

                    let fileSuppressionIndex = SuppressionIndex(
                        locations: prePasResult.suppressionLocations
                    )

                    // Phase B: string scanning (with suppression)
                    let result = scanner.scan(
                        source: source,
                        filePath: fileURL.path,
                        suppressionIndex: fileSuppressionIndex
                    )

                    result.diagnostics.forEach { engine.emit($0) }

                    // Count suppression-related notes
                    suppressedStringCount += result.diagnostics.filter {
                        $0.severity == .note &&
                        $0.message.contains("excluded localization function")
                    }.count

                    if !result.detectedStrings.isEmpty {
                        fileResults.append((filePath: fileURL.path, strings: result.detectedStrings))
                    }

                    if config.incremental {
                        let hash = (try? IncrementalScanCache.contentHash(of: fileURL)) ?? ""
                        cache.entries[cacheKey] = ScanCacheEntry(
                            contentHash:                    hash,
                            swiftl10nVersion:               SwiftL10nCoreVersion.current,
                            detectedStrings:                result.detectedStrings,
                            diagnostics:                    result.diagnostics,
                            existingLocalizationDetections: prePasResult.detections,
                            suppressionLocations:           Array(prePasResult.suppressionLocations)
                        )
                        cacheModified = true
                    }
                } catch {
                    engine.emit(.error, "Cannot read \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        // Persist cache if any entry was added or replaced
        if config.incremental && cacheModified {
            try? IncrementalScanCache.save(cache, to: cacheURL)
        }

        let namespaces = NamespaceInferrer().infer(from: fileResults)

        return PipelineResult(
            scannedFiles:             scannedFileCount,
            namespaces:               namespaces,
            diagnostics:              engine.diagnostics,
            cacheHits:                cacheHits,
            existingLocalizationCount: existingLocalizationCount,
            suppressedStringCount:    suppressedStringCount,
            migrationMode:            effectiveMode
        )
    }

    // MARK: - File Collection

    private func collectSwiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if !isExcluded(url) { results.append(url) }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func isExcluded(_ url: URL) -> Bool {
        guard !config.exclude.isEmpty else { return false }
        // Resolve symlinks on both sides so /var/folders and /private/var/folders compare equal
        let absolutePath = url.resolvingSymlinksInPath().path
        let basePath     = baseURL.resolvingSymlinksInPath().path
        let relativePath = absolutePath.hasPrefix(basePath + "/")
            ? String(absolutePath.dropFirst(basePath.count + 1))
            : absolutePath

        return config.exclude.contains { pattern in
            ScanPipeline.excludes(relativePath: relativePath, pattern: pattern)
        }
    }

    /// Returns `true` if `relativePath` is excluded by `pattern`.
    ///
    /// - Non-glob patterns (no `*` or `?`) are treated as directory prefixes:
    ///   `Sources/Generated` excludes any file inside that directory.
    /// - Glob patterns (`*`, `**`, `?`) are matched with `GlobMatcher`.
    internal static func excludes(relativePath: String, pattern: String) -> Bool {
        let clean = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern

        if !clean.contains("*"), !clean.contains("?") {
            // Plain prefix / exact path
            return relativePath == clean || relativePath.hasPrefix("\(clean)/")
        }

        return GlobMatcher.matches(pattern: clean, path: relativePath)
    }

    // MARK: - Helpers

    private func resolvedURL(for path: String) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : baseURL.appendingPathComponent(path)
    }
}
