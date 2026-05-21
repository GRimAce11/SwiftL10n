# Changelog

All notable changes to SwiftL10n are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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

[Unreleased]: https://github.com/GRimAce11/SwiftL10n/compare/0.1.0...HEAD
[0.1.0]: https://github.com/GRimAce11/SwiftL10n/releases/tag/0.1.0
