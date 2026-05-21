# Changelog

All notable changes to SwiftL10n are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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

[Unreleased]: https://github.com/GRimAce11/SwiftL10n/compare/0.4.1...HEAD
[0.4.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.3.1...0.4.0
[0.3.1]: https://github.com/GRimAce11/SwiftL10n/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/GRimAce11/SwiftL10n/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/GRimAce11/SwiftL10n/releases/tag/0.1.0
