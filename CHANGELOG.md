# Changelog

All notable changes to SwiftL10n are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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

[Unreleased]: https://github.com/GRimAce11/SwiftL10n/compare/0.2.0...HEAD
[0.2.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/GRimAce11/SwiftL10n/releases/tag/0.1.0
