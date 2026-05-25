# Changelog

All notable changes to SwiftL10n are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.9.0] — 2026-05-22

### Added

- **Parallel file scanning** — `ScanPipeline.run()` is now `async throws`. Files are scanned concurrently via `withTaskGroup`; each task runs `ExistingLocalizationDetector` + `StringScanner` independently. Results are sorted by resolved path for deterministic namespace order. Cache reads use a value-type snapshot (`Sendable`) safe for concurrent access; cache writes are sequential after task completion.

- **`PipelineResult.scanDuration: TimeInterval`** — wall-clock time from `run()` invocation to result. Shown as `"0.34s"` in console output.

- **Cache hardening — stale-entry pruning** — on every incremental run, cache entries whose source file no longer exists are removed. `PipelineResult.staleEntriesRemoved: Int` reports the count. Eliminates ghost cache entries that accumulated when files were renamed or deleted between runs.

- **Namespace collision detection** — `NamespaceInferrer.inferDetailed(from:strategy:) -> InferenceResult` returns both the final `[Namespace]` and a `[Diagnostic]` of `.warning` entries, one per set of files that infer to the same namespace name. The existing `infer(from:)` entry point is unchanged — it calls `inferDetailed` with `.file` strategy and returns only the namespaces.

- **`NamespaceStrategy` config enum** — three values configurable via `namespace_strategy:` in `.swiftl10n.yml`:
  - `file` (default) — strip the SwiftUI/UIKit suffix from the file name. Pre-v0.9 behavior, zero breaking change.
  - `directory` — always prefix with the immediate parent directory name (`Payment/SettingsView.swift` → `PaymentSettings`). Skips generic directory names (`Sources`, `Views`, `Screens`, etc.).
  - `auto` — `file` when all names are unique; `directory`-qualified on collision. Recommended for multi-module projects.

- **`JSONReporter`** — `scanned` object gains `scan_duration_seconds: Double` and `stale_entries_removed: Int`.

- **21 new tests** across 2 new test files (total: 392):
  - `NamespaceCollisionTests` — no-collision passthrough, collision warning diagnostic, `.file`/`.auto`/`.directory` strategy behavior, generic-directory skip, YAML config decoding, pipeline integration.
  - `ParallelScanTests` — concurrent correctness (5-file scan), deterministic namespace order across two parallel runs, empty-directory zero-string result, `scanDuration > 0`, `staleEntriesRemoved` after file deletion with incremental cache.

### Changed

- `ScanPipeline.run()` is now `async throws` (previously `throws`). All callers must `await` the result. `ScanCommand` and `SwiftL10nCommand` are promoted to `AsyncParsableCommand`.
- `ConfigTests`, `ScanPipelineTests`, `MigrationModeTests`, and `IncrementalScanCacheTests` updated to `async throws` to match the new `run()` signature.
- Version bumped to `0.9.0`; all 0.8.x incremental cache entries auto-invalidated.

---

## [0.8.0] — 2026-05-22

### Added

- **`// swiftl10n:ignore` inline suppression** — any string literal on a line containing `swiftl10n:ignore` is dropped from scan results. A `.note` diagnostic is emitted to confirm the suppression fired. Honoured automatically by `StringScanner.scan()` with zero configuration — no new API, no flags needed. Both `FunctionCallExprSyntax` (SwiftUI) and `SequenceExprSyntax` (UIKit property assignments) are suppressed. `// swiftl10n:ignore — reason here` works too (arbitrary text after the marker is ignored).

- **`ScoreExplanation`** — new `Sendable, Codable, Equatable, Hashable` model returned by `ConfidenceScorer.explain()`. Captures: `base` (rule's starting confidence), `factors: [Factor]` (each named delta applied), `final` (clamped result). `Factor` has `reason: String` and `delta: Double`. `summary` property produces a human-readable breakdown: `"+2% multi-word phrase, +1% title case, -4% short (3 chars)"`.

- **`ConfidenceScorer.explain(value:baseConfidence:enclosingContext:) -> ScoreExplanation`** — full scoring breakdown. `score()` is now a thin wrapper calling `explain()` and returning `.final`. Every factor previously computed as an anonymous delta is now a named `Factor` (e.g. `"very short (2 chars)"`, `"inside SettingsView (View family)"`, `"all-caps"`, `"contains digits"`).

- **`DetectedString.scoreExplanation: ScoreExplanation?`** — populated by `StringScannerVisitor` on every detection; `nil` only for manually constructed `DetectedString` values (e.g. in tests). Fully `Codable`, included in incremental cache entries.

- **`DetectedString.suggestedPropertyName: String`** — computed extension property. Derives the camelCase Swift method name from `value` and `context` (same algorithm as `CodeGenerator`): `"Delete Account"` in a `Button` → `"deleteAccountButtonTitle"`. No storage, no Codable impact, no configuration needed.

- **`--verbose` confidence breakdown** — when `--verbose` is set, each detected string now shows its score explanation and fix suggestion on separate indented lines:
  ```
  [Text] "Delete Account"  95% — SettingsView.swift:42:13
      score: +2% multi-word phrase, +1% starts uppercase
      → i18n.<Namespace>.deleteAccount()
  ```

- **`--format github`** — new `OutputFormat` case. Emits GitHub Actions annotation syntax: `::warning file=…,line=…,col=…,title=SwiftL10n::…` for each warning/error diagnostic; `::notice title=SwiftL10n::…` for the scan summary. Use in CI:
  ```yaml
  - run: swiftl10n scan --format github
  ```

- **`ImageResource` opt-in** — `assets.use_image_resource: true` in config generates type-safe `ImageResource` accessors instead of `Image` functions for image assets:
  ```swift
  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  public static var profileIcon: ImageResource {
      ImageResource(name: "profile_icon", bundle: .main)
  }
  ```
  Colors are unaffected. Only image assets get `ImageResource` accessors. Default: `false` — no breaking change.

- **`InlineSuppression`** — new `Sendable` type in `SwiftL10nCore/Detection/`. Scans source text in O(lines) time; returns O(1) line-number lookup. Used internally by `StringScanner`; no external API change needed.

- **30 new tests** across 3 new test files:
  - `InlineSuppressionTests` — comment parsing, same-line suppression, multi-line, trailing text, `StringScanner` integration (SwiftUI + UIKit), emitted note diagnostic.
  - `ConfidenceExplanationTests` — base/final accuracy, named factors, `ScoreExplanation.summary`, `DetectedString` integration, `suggestedPropertyName` per context, Codable round-trip.
  - `ImageResourceTests` — config decoding, `@available` annotation, `ImageResource` vs `Image` output, colors unaffected, namespaced path, config round-trip.

### Changed

- `ConfidenceScorer` internals refactored to use `Accumulator` struct; all deltas now carry named reasons. The public `score()` API is unchanged (still returns `Double`); `explain()` is the new first-class method.
- `JSONReporter.StringEntry` gains `suggested_property_name: String` and `score_explanation: ScoreExplanation?` fields. The `swiftl10n_version` field now tracks `SwiftL10nCoreVersion.current` dynamically instead of a hardcoded string.
- `--verbose` console format: confidence shown as `95%` (not `0.95`) and now includes score breakdown and fix suggestion lines.
- `AssetsOutputConfig` gains `use_image_resource: Bool` (default: `false`). `AssetCodeGenerator.Configuration` gains matching field. Existing asset configs are unaffected.
- Version bumped to `0.8.0`; all 0.7.x incremental cache entries auto-invalidated.

### Fixed

- **README roadmap** — duplicate `v1.0` row corrected to `v1.1` (resource consistency stays `v1.0`; API stability contract moved to `v1.1`).
- **`JSONReporter` version** — `swiftl10n_version` was hardcoded as `"0.5.2"` since initial implementation. Now reads `SwiftL10nCoreVersion.current` at runtime, so JSON output always reflects the running library version.
- **`JSONReporter` missing migration fields** — `scanned` object now includes `existing_localized` and `migration_mode`, which were present in `PipelineResult` but not serialized.
- **`ConfigTests` incomplete coverage** — `testDefaultConfigValues()` now asserts all v0.7.0 defaults (`mergeStrategy`, `migration.mode`, `existingLocalization`); `testRoundTripEquality()` exercises all new config fields.
- **`InitCommand` YAML template** — generated `.swiftl10n.yml` now includes commented `existing_localization`, `migration`, and `merge_strategy` sections so developers see the full config surface without consulting the README.
- **`_ = try? await SwiftL10n.scan(…)`** — all README and doc-comment examples updated to suppress the "result of `try?` is unused" compiler warning. `@discardableResult` applies to the direct return value; `try?` produces `Optional<ScanResult>` which the compiler tracks separately.

---

## [0.7.0] — 2026-05-22

### Added

- **`ExistingLocalizationDetector`** — structural pre-pass `SyntaxVisitor` that recognizes existing localization call sites before `StringScanner` runs. Detects member-access chains (`L10n.Settings.save`, `i18n.Common.cancel`) and function calls (`i18n.Settings.title()`) by reconstructing dot-paths from nested `MemberAccessExprSyntax` trees. Uses prefix-and-boundary pattern matching: `"L10n."` matches `L10n.save` but not `L10nHelper.save`. Configurable via `existing_localization.patterns` in `.swiftl10n.yml`. Coexists with SwiftGen, R.swift, NSLocalizedString wrappers, and any custom enum-based system.

- **`SuppressionIndex`** — `O(1)` `Set<SourceLocation>` lookup table built from string literal positions found inside excluded functions (e.g., the `"Save"` in `NSLocalizedString("Save", comment: "")`). Passed into `StringScannerVisitor`; suppression is diagnostic-only — it never mutates AST traversal order or rule evaluation.

- **`ExistingLocalizationDetector.Config`** — two fields: `patterns: [String]` (namespace roots to recognize) and `excludeArgumentsOf: [String]` (function names whose string literal arguments are added to the suppression index). Both default to empty; the pre-pass is zero-cost when unconfigured.

- **`FileRegionMerger`** — marker-based additive merge strategy. `merge(existing:newContent:)` replaces only the content between `// MARK: - SwiftL10n Generated BEGIN` and `// MARK: - SwiftL10n Generated END` markers, preserving all manually-written code above and below. Returns `nil` when markers are absent (first write). `wrap(_:)` adds the markers on initial generation.

- **Migration modes** — three modes controlled by `migration.mode` in config and `--migration-mode` CLI flag:
  - `audit` (default) — current behavior; reports all hardcoded strings; zero breaking change for existing users.
  - `incremental` — runs `ExistingLocalizationDetector`; reports only strings not already covered by configured patterns.
  - `strict` — same as incremental, plus exits non-zero if any hardcoded string is found; CI enforcement.

- **`merge_strategy` on `OutputConfig`** — `overwrite` (default, current behavior) replaces the entire generated file; `region` uses `FileRegionMerger` to preserve manual code on every regeneration.

- **`Diagnostic.Severity.suggestion`** — new severity below `.warning`; never fails CI and is shown only in verbose mode. Reserved for future opt-in advisories (`potentialDuplicate`, `legacyLocalizationPattern`).

- **`--migration-mode` CLI flag** on `swiftl10n scan` — overrides `migration.mode` from config for the current run. Accepts `audit`, `incremental`, `strict`.

- **`PipelineResult.existingLocalizationCount`** — total recognized existing localization call sites across all scanned files; shown in console output when > 0.

- **`PipelineResult.suppressedStringCount`** — string literals skipped because they appeared inside an excluded function call.

- **`PipelineResult.migrationMode`** — the mode used for the run; echoed in JSON output and console.

- **`ScanCacheEntry.existingLocalizationDetections`** and **`ScanCacheEntry.suppressionLocations`** — pre-pass results are now cached alongside string detections; cache miss cost is paid only once per file.

- **53 new tests** across 4 new test files:
  - `ExistingLocalizationDetectorTests` — dot-path reconstruction, boundary-safe pattern matching, call vs member-access kind, sub-expression deduplication, multi-pattern detection, suppression location recording, real-world SwiftGen coexistence fixture, location accuracy.
  - `SuppressionIndexTests` — O(1) lookup, file/line/column precision, empty index, merging, integration with detector output.
  - `MigrationModeTests` — YAML decoding of all modes and patterns, pipeline mode propagation, existing pattern recognition accumulation, suppression integration, backwards compatibility with minimal config.
  - `MergeStrategyTests` — marker replacement, manual code preservation above/below region, whitespace handling, nil on missing markers, reversed markers, first-write wrap, round-trip stability across multiple regenerations.

- **Demo app** updated: "Partial" fixture demonstrating a file with mixed hardcoded strings and `L10n.*` call sites; `ScanViewModel` now runs `ExistingLocalizationDetector` alongside `StringScanner` and exposes `recognizedCount`; results pane shows both gap count and recognized call-site count.

### Changed

- `SwiftL10nConfig` gains two new top-level sections: `existing_localization` (patterns, exclude_arguments_of) and `migration` (mode). Both use `decodeIfPresent` with empty/audit defaults — every existing `.swiftl10n.yml` loads without modification.
- `OutputConfig` gains `merge_strategy` (default: `overwrite`) — existing generated files are overwritten as before unless `region` is explicitly set.
- `StringScanner.scan(source:filePath:)` and `scan(filePath:)` gain an optional `suppressionIndex: SuppressionIndex` parameter (default: `.empty`). Call sites without suppression are unchanged.
- `ScanCommand` console output reports recognized existing localization count when > 0.
- `ScanCommand` exits non-zero in `strict` mode if `totalStrings > 0`, independent of `--fail-on`.
- `JSONReporter` handles `Diagnostic.Severity.suggestion` (mapped to `SL000` / `"note"`).
- Version bumped to `0.7.0`; all 0.6.x incremental cache entries are automatically invalidated.

### Fixed

- `_ = try? await SwiftL10n.scan(...)` — all README and doc-comment examples updated to use `_ =` to suppress the "result of `try?` is unused" compiler warning. `@discardableResult` applies to the direct return value; `try?` produces `Optional<ScanResult>` which is a distinct expression the compiler tracks separately.

---

## [0.6.2] — 2026-05-21

### Fixed

- **iOS build error** — `homeDirectoryForCurrentUser` is macOS-only. Replaced with `NSHomeDirectory()` in `ConfigLoader.swift`, `StringsGenerator.swift`, and `AssetsGenerator.swift`. Xcode compiles all package targets for all declared platforms, so this caused a compile error in any iOS project that added `SwiftL10nCore`. `NSHomeDirectory()` is available on macOS, iOS, tvOS, and watchOS and returns the same value on macOS.

### Added (since v0.6.1)

- **`SwiftL10n.scan(projectPath:)`** — unified entry point. One call generates both `i18n.swift` and `Assets.swift`, runs asset validation, and writes to `projectPath/Generated/` by default. Replaces the two-call `generateStrings()` + `generateAssets()` pattern.
- **`generateAssets(sourcesPath:outputPath:enumName:)`** — top-level free function for standalone `Assets.swift` generation, matching the `generateStrings()` pattern.
- **`AssetsGenerator`** — struct wrapper (mirrors `StringsGenerator`) for programmatic asset generation.

---

## [0.6.1] — 2026-05-21

### Added

- **`AssetCodeGenerator`** — generates `Assets.swift` from an `AssetCatalog`. Source of truth is the parsed catalog only, not detected source references: every asset declared in the catalog gets a typed accessor regardless of whether it is already referenced in code. Output is deterministic (sorted), namespace-aware (nested Swift enums mirror catalog group hierarchy), and collision-safe (duplicate identifiers receive `_2`, `_3` suffixes).
- **Generated API style: `static func` returning `Image`/`Color`** (iOS 13+ compatible, matches `i18n` generation pattern). Example: `Assets.Icons.profileIcon()`, `Assets.primaryBlue()`.
- **Identifier conversion** — asset stems → camelCase Swift identifiers: `profile_icon` → `profileIcon`, `PrimaryBlue` → `primaryBlue`, `app-icon` → `appIcon`. Digit-leading stems get a `_` prefix. Namespace group names → PascalCase Swift type names: `my-icons` → `MyIcons`.
- **`SwiftL10nConfig.AssetsOutputConfig`** — new config section in `.swiftl10n.yml`: `assets.enabled`, `assets.path`, `assets.enum_name`. Disabled by default; set `enabled: true` to activate asset generation during `swiftl10n scan`.
- **`swiftl10n scan --assets-output <path>`** — CLI flag to generate `Assets.swift` for the current run without modifying config.
- **`swiftl10n init`** YAML template updated to include the `assets` section with commented defaults.
- **30 new tests** — `AssetCodeGeneratorTests` (identifier/type-name conversion, empty catalog, images, colors, mixed, namespace-aware, deep nesting, collisions, custom config, determinism, sorting, file structure) and `AssetsOutputConfigTests` (YAML decode, defaults). 282 total, 0 failures.

### Changed

- `ScanCommand` now runs asset generation after localization scan when `assets.enabled: true` in config or `--assets-output` flag is passed.
- `swiftl10n init` YAML template includes `assets:` section with `enabled: false` default.

---

## [0.6.0] — 2026-05-21

### Added

- **`AssetCatalogParser`** — walks any `.xcassets` bundle and extracts all named image (`.imageset`) and color (`.colorset`) assets. Handles Xcode's `provides-namespace` group property so namespaced assets like `"Icons/profile_icon"` are resolved correctly. `.appiconset`, `.symbolset`, and `.dataset` entries are intentionally skipped — they are not accessed by name in user code. `findCatalogs(in:)` locates every `.xcassets` in a directory tree without recursing into bundles; `parseCatalogs(in:)` merges them into one.
- **`AssetCatalog`** — `Sendable` model with `imageNames: Set<String>`, `colorNames: Set<String>`, `contains(image:)`, `contains(color:)`, `merged(_:)`, and `count`.
- **`AssetScanner`** — SwiftSyntax visitor that detects named asset references in Swift source: `Image("name")`, `Image(decorative: "name")`, `Color("name")` (SwiftUI), `UIImage(named:)`, `UIColor(named:)` (UIKit). Does **not** apply `FalsePositiveFilter` — asset names are intentionally identifier-like and would be incorrectly rejected.
- **`AssetScanner.validate(_:against:)`** — compares detected references to the parsed catalog and returns a `.warning` diagnostic for every name absent from the catalog. This is the key differentiator: SwiftGen and R.swift generate typed accessors *from* a catalog; SwiftL10n detects calls *to* a catalog and flags missing names — a gap neither tool covers.
- **`DetectedAssetReference`**, **`AssetType`**, **`AssetContext`** — model types for the asset detection layer. `AssetContext` covers `swiftUIImage`, `swiftUIImageDecorative`, `swiftUIColor`, `uiImageNamed`, `uiColorNamed`.
- **29 new tests** — `AssetCatalogParserTests` (imageset/colorset, appiconset/symbolset ignored, groups without namespace, groups with namespace, nested namespaces, `findCatalogs`, `merged`) and `AssetScannerTests` (all five call-site forms, `Image(systemName:)` excluded, interpolated names excluded, multi-reference file, fully-qualified `SwiftUI.Image`, validation pass/fail/partial). 252 total, 0 failures.

---

## [0.5.2] — 2026-05-21

### Added

- **`IncrementalScanCache`** — CryptoKit SHA-256 per-file hashing. When `incremental: true` in `.swiftl10n.yml`, unchanged files are served from `.build/swiftl10n-cache.json` without re-parsing. Cache entries are invalidated automatically when the file content changes or `SwiftL10nCoreVersion` bumps.
- **`ScanCache` / `ScanCacheEntry`** — `Sendable & Codable` structs. `ScanCache.isValid(for:hash:)` validates both content hash and library version in one call. Cache is written atomically; intermediate directories are created automatically.
- **`SwiftL10nCoreVersion.current`** — version constant embedded in every cache entry for library-level invalidation.
- **`Codable` on all model types** — `DetectedString`, `SourceLocation`, `EnclosingContext`, `Diagnostic`, `Diagnostic.Severity`, `DetectionContext` (custom coding for `unknownUIContext(callee:)`) are now fully `Codable`. Enables cache serialisation and future JSON export of raw scan results.
- **`PipelineResult.cacheHits`** — count of files served from cache; shown in console output `(N cached)` and in JSON `scanned.cache_hits`.
- **14 new tests** — hashing (known SHA-256 vector, consistency, change detection), `ScanCache` validation, round-trip encode/decode with all context types, `IncrementalScanCache` I/O, and two end-to-end integration tests (warm cache → 0 rescans; modified file → 0 cache hits). 223 total, 0 failures.

---

## [0.5.1] — 2026-05-21

### Added

- **`ScanPipeline`** — reusable orchestration layer extracted from `ScanCommand`. Takes a `SwiftL10nConfig` + base URL, returns a `PipelineResult` (scannedFiles, namespaces, diagnostics, totalStrings, warningCount, errorCount). Usable programmatically without the CLI.
- **`GlobMatcher`** — full gitignore-style glob matching: `*` (no slash crossing), `**` (any depth), `?` (single char). Replaces Phase-1 prefix-only exclusion in `ScanPipeline`.
- **`--format json`** flag on `swiftl10n scan` — serializes the full result to stdout as structured JSON (schema version, stats, diagnostics with codes `SL001`/`SL002`, namespaces with per-string context and confidence). Pipe to `jq` or save as a CI artefact.
- **`--fail-on`** flag on `swiftl10n scan` — `errors` (default), `warnings` (exit non-zero on any warning or error), `never` (always succeed). Useful for CI ratchets.
- **29 new tests** — `GlobMatcherTests` (16 cases covering `*`, `**`, `?`, edge cases), `ExclusionMatchingTests` (4 integration cases via `ScanPipeline.excludes`), `ScanPipelineTests` (9 end-to-end cases: multi-file scan, confidence filtering, directory exclusion, glob exclusion). 209 total, 0 failures.

### Changed

- `ScanCommand` is now a thin adapter: config loading + CLI override merging, then delegates to `ScanPipeline` for all scanning work.
- `CodeGenerator` in `ScanCommand` now reads `enumName` / `tableName` from the resolved config (respects `.swiftl10n.yml` settings).

---

## [0.5.0] — 2026-05-21

### Added

- **`.swiftl10n.yml` config file support** — project-level configuration for sources, output path, confidence threshold, exclusions, and incremental mode. All fields are optional with sensible defaults; a minimal file needs only `sources`.
- **`swiftl10n init` command** — generates a commented `.swiftl10n.yml` in the current directory. Accepts `--sources`, `--output`, `--min-confidence`, and `--force` flags.
- **`SwiftL10nConfig`** — `Sendable & Codable` model with nested `OutputConfig`; supports snake_case YAML keys (`minimum_confidence`, `enum_name`, `table_name`) and full round-trip encode/decode.
- **`swiftl10n scan` config-aware** — discovers `.swiftl10n.yml` by walking up from the invocation directory (stops at `Package.swift`, `.git`, `.xcworkspace`). CLI flags always override config values. Path argument is now optional when config provides `sources`.
- **Glob exclusion (Phase 1)** — `exclude` patterns matched against scanned paths. Supports prefix paths (`Sources/Generated`), extension wildcards (`*.generated.swift`), and any-depth prefix (`**/Generated`). Full glob matching arrives in v0.5.1.
- **Yams 5.x** dependency added to the CLI executable and test targets.
- **18 new tests** — `ConfigTests` (YAML decode, round-trip, defaults) and `ConfigLoaderTests` (discovery, load, validation) covering all config surface area.

### Changed

- `swiftl10n scan <path>` path argument is now **optional**. When omitted, sources come from `.swiftl10n.yml`. Existing scripts that pass a path continue to work unchanged.
- `swiftl10n --version` now reports `0.5.0`.

---

## [0.4.1] — 2026-05-21

### Fixed

- **Duplicate function names in generated code** — strings like `"Continue"` and `"Continue →"` no longer produce two identically-named `static func` declarations (compile error). The cleaner string (fewest decorative characters) wins and is used as the localisation key; the decorated variant is silently dropped.
- **Decorative characters (`→ ← ↑ ↓ • …`) added to the word-split separator list** — symbols like arrows are now stripped when building camelCase function names, so `"Next →"` correctly produces `nextButtonTitle()` instead of a name containing noise.

### Added

- `CodeGeneratorTests` — 6 tests covering deduplication, decorator stripping, and unique-name preservation.

---

## [0.4.0] — 2026-05-21

### Changed (breaking)

- **`RuleEngine.default` now includes all SwiftUI + UIKit rules** — no `ruleEngine:` parameter
  needed anywhere. `StringScanner()` detects strings from any project type automatically.
- **Generated file renamed `Strings.swift` → `i18n.swift`** to match the `enum i18n { }` it contains.
  Update your output path to `"\(projectPath)/Generated/i18n.swift"` and remove the old file from your Xcode target.
- **`generateStrings()` `ruleEngine:` parameter removed** — the function signature is now just
  `generateStrings(sourcesPath:outputPath:minimumConfidence:)`.

### Removed

- `RuleEngine.uikit` and `RuleEngine.full` presets — superseded by the unified `RuleEngine.default`.

### Fixed

- UIKit strings were not detected when calling `generateStrings()` without an explicit `ruleEngine:`
  (the old default was SwiftUI-only).

### Demo app

- SwiftUI / UIKit segmented picker added — switch between fixtures to see both frameworks detected.
- `StringRowView` badge colours updated for all UIKit `DetectionContext` cases.

---

## [0.3.1] — 2026-05-21

### Added

- `ruleEngine` parameter on `generateStrings(sourcesPath:outputPath:ruleEngine:)` and `StringsGenerator.init` — pass `.uikit` or `.full` without constructing a scanner manually

### Changed

- README Detection rules section split into SwiftUI (`RuleEngine.default`) and UIKit (`RuleEngine.uikit` / `.full`) tables, covering all 22 supported patterns

---

## [0.3.0] — 2026-05-21

### Added

- **UIKit string detection** — 18 new tests, 158 total passing
  - **`PropertyAssignmentRule` protocol** — new visitor for `property = "string"` expressions; handles `label.text`, `textField.placeholder`, `navigationItem.title`, `self.title`, bare `title`
  - **`UIKitPropertyAssignmentRule`** — maps `text` → `.uiLabel`, `placeholder` → `.uiTextFieldPlaceholder`, `title` → `.uiNavigationTitle`
  - **6 new function-call rules** — `UIButtonSetTitleRule`, `UIAlertControllerTitleRule`, `UIAlertControllerMessageRule`, `UIAlertActionRule`, `UIBarButtonItemRule`, `UITabBarItemRule`
  - **8 new `DetectionContext` cases** — `.uiLabel`, `.uiButtonTitle`, `.uiTextFieldPlaceholder`, `.uiNavigationTitle`, `.uiAlertTitle`, `.uiAlertMessage`, `.uiAlertAction`, `.uiTabBarItem`
  - **`RuleEngine.uikit`** — UIKit-only preset; use with `StringScanner(ruleEngine: .uikit)`
  - **`RuleEngine.full`** — SwiftUI + UIKit combined; use with `StringScanner(ruleEngine: .full)`
  - **`UIAlertController` detects both strings** — title and message extracted from a single call site; visitor no longer breaks on first match for function calls
  - **UIKit integration guide** in README — `AppDelegate`, `SceneDelegate`, and `UIViewController` entry points with copy-paste `scanStrings()` function

### Fixed

- **Sandbox permission error** — `GeneratorError.permissionDenied` now prints a step-by-step fix guide instead of the raw system error
- **`scanStrings()` guarded with `#if DEBUG && !targetEnvironment(simulator)`** — prints a clear skip message when accidentally run on a real device; never runs in release
- **Single `projectPath` variable** — `outputPath` is derived from `projectPath`, users change one line not two

### Changed

- `isDirect()` and `memberName()` helpers promoted from `private` to `internal` so `UIKitRules.swift` can share them without duplication

---

## [0.2.0] — 2026-05-21

### Added

- **`generateStrings(sourcesPath:outputPath:minimumConfidence:)`** — top-level async free function; call it from any SwiftUI view with two paths, no extra setup
- **`StringsGenerator`** — high-level `Sendable` struct wrapping the full scan → infer → extract → generate → write pipeline; exposes `run() async throws -> Result`
- **`CommonStringExtractor`** — detects string values shared across 2+ source files and lifts them into a dedicated `i18n.Common` namespace, generated once and usable everywhere; includes `ExtractionResult` with per-value origin map
- **`--output` and `--min-confidence` CLI flags** — `swiftl10n scan Sources/ --output Strings.swift --min-confidence 0.85`
- **Console scan output** — every detected string is printed during generation with context, confidence %, and interpolation warnings; common strings report shows which files they came from
- **`SwiftL10nDemo` example app** — macOS 14 SwiftUI app in `Examples/SwiftL10nDemo/` with live scanner, confidence slider, and code generation preview; opens as both `.xcodeproj` and Swift Package
- **Production Guide** — `Documentation/ProductionGuide.md` covering 13 steps from install through CI enforcement, custom rules, and incremental migration
- **`ToggleRule`** — detects `Toggle("label", isOn:)` as the 9th built-in detection rule

### Changed

- **Code generation** — `static var … : String { … }` replaced with `static func …() -> String { … }` using `String(localized:table:bundle:comment:)` (modern Swift API, iOS 16+ / macOS 13+)
- **`i18n.Common` always generated first** — shared strings appear at the top of `Strings.swift` before per-namespace extensions
- **Platform support expanded** — package now declares iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+ in addition to macOS 13+; resolves SwiftSyntax minimum version conflict when adding the package to iOS projects

### Fixed

- `FalsePositiveFilter` check ordering — reverse-DNS strings (`com.example.app`) now correctly return `.analyticsKey` instead of `.dotSeparatedIdentifier`; `SCREAMING_CASE` now correctly returns `.allCapsConstant` instead of `.snakeCaseIdentifier`
- Demo app deployment target restored to macOS 14.0 (`@Observable` requirement)

---

## [0.1.0] — 2026-05-21

### Added

#### Detection engine
- Rule-based detection architecture (`DetectionRule` protocol + `RuleEngine`)
- 9 built-in SwiftUI detection rules: `Text`, `Button`, `Label`, `Toggle`, `TextField`,
  `.navigationTitle` / `.navigationBarTitle`, `.alert`, `.confirmationDialog`, `.accessibilityLabel`
- `ArgumentSelector` — `.firstUnlabeled` correctly skips opt-out forms like `Text(verbatim:)`
- `FalsePositiveFilter` — deterministic exclusion of URLs, file paths, SF Symbol names,
  reverse-DNS strings, `snake_case`, `camelCase`, and `SCREAMING_CASE` identifiers
- `ConfidenceScorer` — additive delta model producing a clamped `0.0–1.0` confidence score
  adjusted for string length, word count, title case, numeric content, and enclosing context
- `ContextExtractor` — walks the SwiftSyntax parent chain to capture the enclosing type,
  property, and function for each detected string
- Interpolation handling — strings with `\(…)` are detected, templated with `{…}` markers,
  flagged `hasInterpolation: true`, and emit a `.warning` diagnostic; skipped in code generation

#### Models
- `DetectedString` — value, location, context, confidence, hasInterpolation, enclosingContext
- `DetectionContext` — 9 typed cases + `unknownUIContext(callee:)` escape hatch
- `EnclosingContext` — typeName, propertyName, functionName; `.empty` singleton
- `Namespace`, `Diagnostic`, `SourceLocation`

#### Tooling
- `NamespaceInferrer` — derives logical namespaces from source file names (strips View/Screen/Page/Controller suffixes)
- `CodeGenerator` — emits a type-safe `enum Strings { enum Namespace { static let … } }` scaffold;
  skips interpolated strings
- `DiagnosticsEngine` — thread-safe collector with severity filtering and formatted console output
- `swiftl10n scan <path>` CLI with `--verbose` and `--quiet` flags

#### Quality
- 130 tests across 10 test files
- Fixture-based integration tests (`settingsView`, `falsePositiveNoise`, `allCallSites`,
  `interpolationMix`, `verbatimOptOut`)
- Swift 6 strict concurrency — fully `Sendable`, zero data races

[Unreleased]: https://github.com/GRimAce11/SwiftL10n/compare/0.9.0...HEAD
[0.9.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.6.2...0.7.0
[0.6.2]: https://github.com/GRimAce11/SwiftL10n/compare/0.6.1...0.6.2
[0.6.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.5.2...0.6.0
[0.5.2]: https://github.com/GRimAce11/SwiftL10n/compare/0.5.1...0.5.2
[0.5.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.5.0...0.5.1
[0.5.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.4.1...0.5.0
[0.4.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.3.1...0.4.0
[0.3.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/GRimAce11/SwiftL10n/releases/tag/0.1.0
