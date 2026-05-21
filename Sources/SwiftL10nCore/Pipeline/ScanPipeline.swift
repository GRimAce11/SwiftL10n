import Foundation

/// Orchestrates the full scan pipeline: file collection → scanning → namespace inference.
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

        /// Sum of strings across all namespaces.
        public var totalStrings: Int { namespaces.reduce(0) { $0 + $1.strings.count } }

        public var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }
        public var errorCount: Int   { diagnostics.filter { $0.severity == .error }.count }
    }

    // MARK: - Configuration

    /// Project-level config (sources, exclusions, confidence, etc.).
    public let config: SwiftL10nConfig
    /// Directory that relative paths in `config` are resolved against —
    /// usually the directory containing `.swiftl10n.yml`, or the cwd.
    public let baseURL: URL

    public init(config: SwiftL10nConfig, baseURL: URL) {
        self.config = config
        self.baseURL = baseURL
    }

    // MARK: - Run

    /// Collect files, scan, and infer namespaces.
    ///
    /// - Parameters:
    ///   - sources: Override `config.sources`. `nil` uses config values.
    ///   - minimumConfidence: Override `config.minimumConfidence`. `nil` uses config value.
    public func run(
        sources: [String]? = nil,
        minimumConfidence: Double? = nil
    ) throws -> PipelineResult {
        let effectiveSources = sources ?? config.sources
        let effectiveConfidence = minimumConfidence ?? config.minimumConfidence

        let scanner = StringScanner(minimumConfidence: effectiveConfidence)
        let engine = DiagnosticsEngine()
        var fileResults: [(filePath: String, strings: [DetectedString])] = []
        var scannedFileCount = 0
        var cacheHits = 0

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
                    cacheHits += 1
                    continue
                }

                // Full scan
                do {
                    let result = try scanner.scan(filePath: fileURL.path)
                    result.diagnostics.forEach { engine.emit($0) }
                    if !result.detectedStrings.isEmpty {
                        fileResults.append((filePath: fileURL.path, strings: result.detectedStrings))
                    }

                    if config.incremental {
                        let hash = (try? IncrementalScanCache.contentHash(of: fileURL)) ?? ""
                        cache.entries[cacheKey] = ScanCacheEntry(
                            contentHash: hash,
                            swiftl10nVersion: SwiftL10nCoreVersion.current,
                            detectedStrings: result.detectedStrings,
                            diagnostics: result.diagnostics
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
            scannedFiles: scannedFileCount,
            namespaces: namespaces,
            diagnostics: engine.diagnostics,
            cacheHits: cacheHits
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
        let basePath = baseURL.resolvingSymlinksInPath().path
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
