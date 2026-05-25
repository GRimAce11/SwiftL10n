import Foundation

/// Orchestrates the full scan pipeline: file collection → pre-pass → parallel scanning
/// → namespace inference → diagnostics.
///
/// `ScanPipeline` is the reusable core extracted from `ScanCommand`. It owns no I/O
/// state and is safe to call multiple times.
///
/// ```swift
/// let pipeline = ScanPipeline(config: config, baseURL: projectRoot)
/// let result = try await pipeline.run()
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
        /// Wall-clock time from `run()` invocation to result.
        public let scanDuration: TimeInterval
        /// Cache entries removed because the corresponding source file no longer exists.
        public let staleEntriesRemoved: Int
        /// Detected source strings absent from the `.xcstrings` catalog.
        /// Zero when no catalog is found.
        public let missingCatalogKeys: Int
        /// Catalog keys with no matching detected source string value.
        /// Zero when no catalog is found or `validateOrphaned` is disabled.
        public let orphanedCatalogKeys: Int
        /// Catalog key groups sharing the same source-language value.
        /// Zero when no catalog is found.
        public let duplicateCatalogGroups: Int
        /// `Image("name")` calls flagged for missing accessibility modifiers.
        /// Zero when `accessibility_audit.enabled` is `false`.
        public let accessibilityWarnings: Int

        /// Sum of strings across all namespaces.
        public var totalStrings: Int { namespaces.reduce(0) { $0 + $1.strings.count } }

        public var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }
        public var errorCount: Int   { diagnostics.filter { $0.severity == .error   }.count }
    }

    // MARK: - Configuration

    public let config: SwiftL10nConfig
    public let baseURL: URL

    public init(config: SwiftL10nConfig, baseURL: URL) {
        self.config  = config
        self.baseURL = baseURL
    }

    // MARK: - Run

    /// Collect files, run the pre-pass and string scanner in parallel, infer namespaces,
    /// and return a complete `PipelineResult`.
    ///
    /// - Parameters:
    ///   - sources: Override `config.sources`. `nil` uses config values.
    ///   - minimumConfidence: Override `config.minimumConfidence`. `nil` uses config value.
    ///   - migrationMode: Override `config.migration.mode`. `nil` uses config value.
    public func run(
        sources: [String]? = nil,
        minimumConfidence: Double? = nil,
        migrationMode: SwiftL10nConfig.MigrationConfig.Mode? = nil
    ) async throws -> PipelineResult {
        let startTime           = Date()
        let effectiveSources    = sources ?? config.sources
        let effectiveConfidence = minimumConfidence ?? config.minimumConfidence
        let effectiveMode       = migrationMode ?? config.migration.mode
        let strategy            = config.namespaceStrategy

        let prePasActive = config.existingLocalization.isActive
            || effectiveMode == .incremental
            || effectiveMode == .strict

        let detector: ExistingLocalizationDetector? = prePasActive
            ? ExistingLocalizationDetector(config: config.existingLocalization.detectorConfig)
            : nil

        let scanner = StringScanner(minimumConfidence: effectiveConfidence)
        let engine  = DiagnosticsEngine()

        // ── 1. Collect all file URLs (sequential) ──────────────────────────────
        var allFiles: [URL] = []
        for source in effectiveSources {
            let sourceURL = resolvedURL(for: source)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
                engine.emit(.error, "Source path not found: \(source)")
                continue
            }
            if isDir.boolValue {
                allFiles += collectSwiftFiles(in: sourceURL)
            } else if sourceURL.pathExtension == "swift" {
                allFiles.append(sourceURL)
            }
        }
        let scannedFileCount = allFiles.count

        // ── 2. Load incremental cache snapshot ────────────────────────────────
        let cacheURL = baseURL.appendingPathComponent(ScanCache.defaultRelativePath)
        var cache: ScanCache = config.incremental
            ? ((try? IncrementalScanCache.load(from: cacheURL)) ?? ScanCache())
            : ScanCache()
        let cacheSnapshot = cache  // value-type copy — safe for concurrent reads

        // ── 3. Parallel scan ──────────────────────────────────────────────────
        let parallelResults: [FileResult] = await withTaskGroup(
            of: FileResult.self,
            returning: [FileResult].self
        ) { group in
            let incrementalEnabled      = config.incremental
            let accessibilityAuditEnabled = config.accessibilityAudit.enabled

            for fileURL in allFiles {
                group.addTask {
                    let cacheKey = fileURL.resolvingSymlinksInPath().path

                    // Try cache hit first
                    if incrementalEnabled,
                       let hash = try? IncrementalScanCache.contentHash(of: fileURL),
                       cacheSnapshot.isValid(for: cacheKey, hash: hash),
                       let entry = cacheSnapshot.entries[cacheKey] {
                        return .cached(
                            cacheKey:          cacheKey,
                            strings:           entry.detectedStrings,
                            diagnostics:       entry.diagnostics,
                            existingCount:     entry.existingLocalizationDetections.count
                        )
                    }

                    // Full scan
                    guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        return .failed(message: "Cannot read \(fileURL.lastPathComponent)")
                    }

                    let detectorResult = detector?.detect(source: source, filePath: fileURL.path)
                        ?? .empty
                    let suppressionIndex = SuppressionIndex(locations: detectorResult.suppressionLocations)
                    let scanResult       = scanner.scan(
                        source: source,
                        filePath: fileURL.path,
                        suppressionIndex: suppressionIndex
                    )
                    let contentHash = IncrementalScanCache.sha256Hex(Data(source.utf8))

                    var allDiagnostics = scanResult.diagnostics
                    if accessibilityAuditEnabled {
                        allDiagnostics += AccessibilityAuditor().audit(source: source, filePath: fileURL.path)
                    }

                    return .scanned(
                        cacheKey:            cacheKey,
                        filePath:            fileURL.path,
                        strings:             scanResult.detectedStrings,
                        diagnostics:         allDiagnostics,
                        existingDetections:  detectorResult.detections,
                        suppressionLocs:     Array(detectorResult.suppressionLocations),
                        contentHash:         contentHash
                    )
                }
            }

            var results: [FileResult] = []
            for await r in group { results.append(r) }
            // Sort by cache key for deterministic namespace ordering
            return results.sorted { $0.sortKey < $1.sortKey }
        }

        // ── 4. Sequential aggregation ─────────────────────────────────────────
        var fileResults: [(filePath: String, strings: [DetectedString])] = []
        var existingLocalizationCount = 0
        var suppressedStringCount     = 0
        var cacheHits                 = 0
        var newEntries: [(key: String, entry: ScanCacheEntry)] = []

        for result in parallelResults {
            switch result {
            case let .cached(key, strings, diags, existingCount):
                diags.forEach { engine.emit($0) }
                if !strings.isEmpty { fileResults.append((filePath: key, strings: strings)) }
                existingLocalizationCount += existingCount
                cacheHits += 1

            case let .scanned(key, filePath, strings, diags, existingDetections, suppressionLocs, hash):
                diags.forEach { engine.emit($0) }
                if !strings.isEmpty { fileResults.append((filePath: filePath, strings: strings)) }
                existingLocalizationCount += existingDetections.count
                suppressedStringCount += diags.filter {
                    $0.severity == .note && $0.message.contains("excluded localization function")
                }.count

                if config.incremental {
                    newEntries.append((key, ScanCacheEntry(
                        contentHash:                    hash,
                        swiftl10nVersion:               SwiftL10nCoreVersion.current,
                        detectedStrings:                strings,
                        diagnostics:                    diags,
                        existingLocalizationDetections: existingDetections,
                        suppressionLocations:           suppressionLocs
                    )))
                }

            case let .failed(message):
                engine.emit(.error, message)
            }
        }

        // ── 5. Cache update + stale entry removal ─────────────────────────────
        var staleEntriesRemoved = 0
        if config.incremental {
            // Apply new entries
            for (key, entry) in newEntries {
                cache.entries[key] = entry
            }
            // Prune entries for files no longer in the scan set
            let validKeys = Set(allFiles.map { $0.resolvingSymlinksInPath().path })
            let staleKeys = Set(cache.entries.keys).subtracting(validKeys)
            for key in staleKeys { cache.entries.removeValue(forKey: key) }
            staleEntriesRemoved = staleKeys.count

            if !newEntries.isEmpty || staleEntriesRemoved > 0 {
                try? IncrementalScanCache.save(cache, to: cacheURL)
            }
        }

        // ── 6. Namespace inference with collision detection ────────────────────
        let inference = NamespaceInferrer().inferDetailed(from: fileResults, strategy: strategy)
        inference.collisionDiagnostics.forEach { engine.emit($0) }

        // ── 7. String catalog validation ──────────────────────────────────────
        var missingCatalogKeys     = 0
        var orphanedCatalogKeys    = 0
        var duplicateCatalogGroups = 0

        let catalog = (try? StringCatalogParser.parseCatalogs(in: baseURL)) ?? .empty
        if !catalog.keys.isEmpty {
            let catResult = StringCatalogValidator().validate(
                namespaces: inference.namespaces,
                against: catalog
            )
            missingCatalogKeys  = catResult.missingCount
            orphanedCatalogKeys = catResult.orphanedCount

            if config.stringCatalog.validateMissing {
                for entry in catResult.missingFromCatalog {
                    engine.emit(Diagnostic(
                        severity: .warning,
                        message: "Detected string \"\(entry.value)\" is absent from the string catalog",
                        location: entry.locations.first
                    ))
                }
            }
            if config.stringCatalog.validateOrphaned {
                for key in catResult.orphanedInCatalog {
                    engine.emit(Diagnostic(
                        severity: .note,
                        message: "Catalog key \"\(key)\" has no detected source usage — may be orphaned"
                    ))
                }
            }

            let dupGroups = DuplicateLocalizationAnalyzer().analyzeCatalog(catalog)
            duplicateCatalogGroups = dupGroups.count
            for group in dupGroups {
                engine.emit(Diagnostic(
                    severity: .suggestion,
                    message: "Duplicate catalog value \"\(group.sharedValue)\" used by "
                           + "\(group.keys.count) keys: \(group.keys.joined(separator: ", "))"
                ))
            }
        }

        // ── 8. Accessibility warning count ────────────────────────────────────
        let accessibilityWarnings = engine.diagnostics.filter {
            $0.severity == .warning
                && $0.message.hasPrefix("Image literal without accessibility modifier")
        }.count

        return PipelineResult(
            scannedFiles:             scannedFileCount,
            namespaces:               inference.namespaces,
            diagnostics:              engine.diagnostics,
            cacheHits:                cacheHits,
            existingLocalizationCount: existingLocalizationCount,
            suppressedStringCount:    suppressedStringCount,
            migrationMode:            effectiveMode,
            scanDuration:             Date().timeIntervalSince(startTime),
            staleEntriesRemoved:      staleEntriesRemoved,
            missingCatalogKeys:       missingCatalogKeys,
            orphanedCatalogKeys:      orphanedCatalogKeys,
            duplicateCatalogGroups:   duplicateCatalogGroups,
            accessibilityWarnings:    accessibilityWarnings
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
    internal static func excludes(relativePath: String, pattern: String) -> Bool {
        let clean = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern

        if !clean.contains("*"), !clean.contains("?") {
            return relativePath == clean || relativePath.hasPrefix("\(clean)/")
        }

        return GlobMatcher.matches(pattern: clean, path: relativePath)
    }

    private func resolvedURL(for path: String) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : baseURL.appendingPathComponent(path)
    }
}

// MARK: - Private task result

private enum FileResult: Sendable {
    case cached(
        cacheKey:      String,
        strings:       [DetectedString],
        diagnostics:   [Diagnostic],
        existingCount: Int
    )
    case scanned(
        cacheKey:           String,
        filePath:           String,
        strings:            [DetectedString],
        diagnostics:        [Diagnostic],
        existingDetections: [ExistingLocalizationDetector.Detection],
        suppressionLocs:    [SourceLocation],
        contentHash:        String
    )
    case failed(message: String)

    var sortKey: String {
        switch self {
        case .cached(let k, _, _, _):       return k
        case .scanned(let k, _, _, _, _, _, _): return k
        case .failed:                        return ""
        }
    }
}
