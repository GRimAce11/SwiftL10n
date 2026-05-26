# SwiftL10n

[![CI](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml/badge.svg)](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%2B%20%7C%20macOS%2013%2B-lightgray.svg)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![SPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

Source-aware infrastructure tooling for Swift codebases: detects hardcoded strings, validates asset references and `.xcstrings` catalogs, audits accessibility completeness, and generates type-safe `i18n.swift` / `Assets.swift` scaffolds.

---

## Overview

SwiftL10n statically analyses your Swift source using SwiftSyntax and detects every hardcoded string that should be localized, and every asset name that does not exist in any `.xcassets` catalog. It runs entirely at the source level — no simulator, no SourceKit, no runtime.

Feed it a directory; get back a typed list of detected strings with confidence scores, missing-asset diagnostics, and generated `i18n.swift` / `Assets.swift` scaffolds ready to drop into your project.

---

## Design Philosophy

SwiftL10n is **source-aware infrastructure validation and generation tooling**. It reads your Swift source, cross-references it against your project's infrastructure, and emits additive, deterministic output. It does not rewrite source, does not speculate, and does not mutate files outside of an explicit `swiftl10n scan` invocation.

Seven principles govern every design decision:

**1. Source-driven analysis.** The Swift source file is always the input. SwiftL10n reads your code and validates it against infrastructure (catalogs, string tables). Infrastructure generates typed accessors as a byproduct of the same analysis — never as the primary goal.

**2. Validation first, generation second.** The primary value is catching errors before they reach production: `Image("missing_icon")` that crashes at runtime, a localization key present in source but absent from the string catalog. Code generation is additive output derived from the same analysis pass.

**3. Additive generation only.** Generated files (`i18n.swift`, `Assets.swift`) supplement your project. They are never required for compilation, never modify existing source, and can be regenerated identically at any time. Deleting them has no effect on your codebase.

**4. Deterministic and explainable.** The same inputs always produce the same outputs on every machine, in every environment, in every CI run. Every diagnostic has a documented, traceable reason — an enumerated case in `FalsePositiveFilter`, a concrete delta in `ConfidenceScorer`. There are no black-box classifiers.

**5. Trust through precision.** One false positive costs more developer trust than ten missed detections. SwiftL10n stays silent when uncertain. The FalsePositiveFilter is conservative by design. Confidence thresholds are configurable. Diagnostics are suppressible. Trust is earned by being right, not by being loud.

**6. CI-safe by default.** No file is written during a build. No source is modified without an explicit command. `--format json` and `--fail-on` make SwiftL10n composable with any CI pipeline without side effects.

**7. Separation of concerns.** Localization infrastructure (`i18n.swift`) and asset infrastructure (`Assets.swift`) are generated through separate, independent pipelines. `i18n.Settings.title()` resolves through the NSBundle translation layer at runtime. `Assets.profileIcon()` loads a pixel buffer from the asset catalog. These operations have different semantics, different failure modes, and must never share a generated namespace.

---

## Features

- **20 detection rules** out of the box — SwiftUI and UIKit detected automatically, no configuration needed
- **Smart false-positive prevention** — SF Symbol names, URLs, file paths, reverse-DNS keys, `snake_case`, `camelCase`, and `SCREAMING_CASE` identifiers are all filtered out
- **Confidence scoring** — every result carries a deterministic `0.0–1.0` score adjusted for string content and enclosing SwiftUI context
- **Interpolation awareness** — `Text("Hello \(name)!")` is detected, templated as `"Hello {…}!"`, and flagged with a warning; it is skipped during code generation
- **Enclosing context** — each string records the surrounding type, property, and function
- **Namespace inference** — derives logical namespaces from file names (`SettingsView.swift` → `Settings`)
- **Code generation** — emits a type-safe `enum i18n { enum Settings { … } }` scaffold using `String(localized:table:bundle:)` (iOS 16+ / macOS 13+)
- **Common string extraction** — strings shared across multiple files are automatically lifted into `i18n.Common`
- **Asset catalog parsing** — recursively walks every `.xcassets` bundle, respects `provides-namespace` groups, extracts all named image and color assets
- **Missing asset diagnostics** — `Image("name")` where `name` is absent from the catalog produces a `.warning` before any runtime crash; neither SwiftGen nor R.swift do this
- **Typed `Assets.swift` generation** — `AssetCodeGenerator` converts the parsed catalog into a type-safe `enum Assets { }` with namespace-aware nested enums (`Assets.Icons.profileIcon()`)
- **Project config file** — `.swiftl10n.yml` at the project root; run `swiftl10n init` to create one
- **Incremental scanning** — SHA-256 per-file hashing skips unchanged files on subsequent runs (`incremental: true` in config)
- **JSON output** — `--format json` produces a structured, versioned schema for CI artefacts and downstream tooling
- **Incremental adoption** — `ExistingLocalizationDetector` recognizes existing localization patterns (`L10n.`, `i18n.`, `Strings.`, `NSLocalizedString`) and skips them in `incremental` mode; production codebases with partial localization work on day one
- **Migration modes** — `audit` (all strings), `incremental` (gaps only), `strict` (CI enforcement)
- **Additive merge strategy** — `merge_strategy: region` preserves manual extensions below the generated block on every regeneration
- **Inline suppression** — `// swiftl10n:ignore` on any line silences that line's detection; a `.note` diagnostic confirms the suppression fired
- **Confidence explanations** — `--verbose` output shows the score breakdown for each detection: `+2% multi-word phrase, +1% title case, -12% very short (3 chars)`
- **Fix suggestions** — every detected string exposes `suggestedPropertyName` (e.g. `deleteAccountButtonTitle`) in verbose output and JSON
- **GitHub Actions annotations** — `--format github` emits `::warning file=…,line=…::` annotations consumed natively by GitHub CI
- **`ImageResource` opt-in** — `use_image_resource: true` in `assets:` config generates `@available(iOS 16, …)` `ImageResource` accessors instead of `Image` functions
- **`.xcstrings` catalog validation** — `StringCatalogParser` parses Xcode 15+ String Catalogs; `StringCatalogValidator` cross-references detected strings against the catalog: warns for strings absent from the catalog (`validate_missing: true`) and notes orphaned keys with no source usage (`validate_orphaned: false`)
- **Duplicate localization analysis** — `DuplicateLocalizationAnalyzer` finds catalog entries sharing the same source-language value (consolidation opportunities) and string values appearing in 2+ namespaces (`i18n.Common` promotion candidates)
- **Accessibility audit** — `AccessibilityAuditor` flags `Image("name")` calls missing `.accessibilityLabel` or `.accessibilityHidden` in the SwiftUI modifier chain; opt-in via `accessibility_audit.enabled: true`
- **Extensible** — add custom detection rules by conforming to `DetectionRule`
- **Swift 6 ready** — strict concurrency enforced, fully `Sendable`, zero data races

---

## Quick Start

Add the package, add one line to your `ContentView`, change one path, run.

### 1. Add the package

**Xcode:** File → Add Package Dependencies → paste the URL:

```
https://github.com/GRimAce11/SwiftL10n.git
```

Xcode shows two products. **Only add `SwiftL10nCore`:**

| Product | What it is | Add to app? |
|---|---|---|
| `SwiftL10nCore` | The library — scanning, validation, and generation API | **Yes ✓** |
| `swiftl10n` | A CLI terminal tool — not a library | No ✗ |

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SwiftL10nCore", package: "SwiftL10n"),
    ]),
]
```

---

### 2. Add one line to your `ContentView`

```swift
import SwiftUI
import SwiftL10nCore

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
            .task {
                #if DEBUG
                let projectPath = "/Users/you/Developer/YourApp/Sources/YourApp"
                _ = try? await SwiftL10n.scan(projectPath: projectPath)
                #endif
            }
    }
}
```

`SwiftL10n.scan()` does everything in one call:
- Scans all `.swift` files for localizable strings
- Validates every `Image("…")` / `UIImage(named:)` reference against your `.xcassets` catalogs
- Writes `Generated/i18n.swift` — typed localization API
- Writes `Generated/Assets.swift` — typed asset API

Run the app once on Simulator or macOS. The Xcode console prints every detected string, every missing asset warning, then confirms both files were written:

```
── SettingsView.swift (5 string(s))
   [navigationTitle] "Settings"  99%
   [Button] "Save"  97%
   [Button] "Delete Account"  97%
   [alert] "Are you sure?"  96%
   [Toggle] "Push Notifications"  95%

── HomeView.swift (3 string(s))
   [Text] "Welcome Back"  99%
   [Button] "Get Started"  97%
   [Button] "Save"  97%

── Asset validation (Assets.xcassets · 32 asset(s))
   ✓ All asset references resolved

── Common strings (shared across multiple files → i18n.Common)
   "Save"  ← Home, Profile, Settings

✓ Created → .../Sources/YourApp/Generated/i18n.swift
✓ 10 string(s) · 3 namespace(s) · 0 warning(s) · 0 missing asset(s)
── Asset generation (Assets.xcassets)
   24 image(s) · 8 color(s)
✓ Created → .../Sources/YourApp/Generated/Assets.swift
```

> **Sandbox error?** If you see *"You don't have permission to save the file…"*:
> 1. Xcode → Your Target → **Signing & Capabilities** → **App Sandbox** → untick **Enable App Sandbox**, or
> 2. Keep the sandbox and add **File Access → User Selected Files → Read/Write**
>
> The `#if DEBUG` guard ensures this code never runs in a release build.

**Remove the `SwiftL10n.scan()` call** after both files are generated. You only need it when regenerating.

Your project layout after running:

```
YourApp/
├── YourApp.xcodeproj
└── Sources/
    └── YourApp/
        ├── ContentView.swift
        ├── HomeView.swift
        ├── SettingsView.swift
        └── Generated/
            ├── i18n.swift      ← localization API, created automatically
            └── Assets.swift    ← asset API, created automatically
```

**Drag both files into your Xcode Project Navigator** and tick your app target — done.

---

### 3. What `Generated/i18n.swift` looks like

Strings shared across multiple files are automatically lifted into `i18n.Common` — generated once, usable everywhere.

```swift
// Auto-generated by SwiftL10n — do not edit.
// swiftlint:disable all

import Foundation

enum i18n {
    fileprivate enum General {
        static let table  = "Localizable"
        static let bundle = Bundle.main
    }
}

// "Save" appeared in Settings, Home, and Profile — generated here once
extension i18n {
    enum Common {

        /// "Save"
        static func save() -> String {
            String(
                localized: "Save",
                table: General.table,
                bundle: General.bundle,
                comment: "Common: Button — Save"
            )
        }

    }
}

extension i18n {
    enum Settings {

        /// "Settings"
        static func settingsNavigationTitle() -> String {
            String(
                localized: "Settings",
                table: General.table,
                bundle: General.bundle,
                comment: "Settings: navigationTitle — Settings"
            )
        }

        /// "Delete Account"
        static func deleteAccountButtonTitle() -> String {
            String(
                localized: "Delete Account",
                table: General.table,
                bundle: General.bundle,
                comment: "Settings: Button — Delete Account"
            )
        }

    }
}
```

---

### 4. Replace hardcoded strings

```swift
// Before
Text("Welcome Back")
Button("Delete Account") { ... }
.navigationTitle("Settings")
Toggle("Push Notifications", isOn: $on)
.alert("Are you sure?", isPresented: $show) { ... }

// After — type i18n. and Xcode autocompletes the namespace
Text(i18n.Home.welcomeBack())
Button(i18n.Settings.deleteAccountButtonTitle()) { ... }
.navigationTitle(i18n.Settings.settingsNavigationTitle())
Toggle(i18n.Settings.pushNotificationsToggleLabel(), isOn: $on)
.alert(i18n.Settings.areYouSureAlertTitle(), isPresented: $show) { ... }
```

---

### 5. What `Generated/Assets.swift` looks like

`SwiftL10n.scan()` generates `Assets.swift` alongside `i18n.swift` — nothing extra to configure. Every asset in every `.xcassets` catalog near your project path gets a typed accessor:

```swift
// Auto-generated by SwiftL10n — do not edit.
// swiftlint:disable all

import SwiftUI

public enum Assets {

    // MARK: - Images

    /// Asset: "logo"
    public static func logo() -> Image { Image("logo") }

}

extension Assets {
    public enum Icons {

        // MARK: - Images

        /// Asset: "Icons/profile_icon"
        public static func profileIcon() -> Image { Image("Icons/profile_icon") }

    }
}

extension Assets {
    public enum Theme {

        // MARK: - Colors

        /// Asset: "Theme/PrimaryBlue"
        public static func primaryBlue() -> Color { Color("Theme/PrimaryBlue") }

    }
}
```

Replace string literals with typed calls:

```swift
// Before
Image("profile_icon")
Color("PrimaryBlue")

// After — type Assets. and Xcode autocompletes the namespace
Assets.Icons.profileIcon()
Assets.Theme.primaryBlue()
```

**Drag `Generated/Assets.swift` into your Xcode Project Navigator** and tick your app target. Generation is from the catalog, not from source: every asset in the catalog gets an accessor, regardless of whether your code has referenced it yet.

> **Namespace-aware:** if an asset group in Xcode has **Provides Namespace** enabled, the generated path mirrors it — `Assets.Icons.profileIcon()` for `Icons/profile_icon`. Groups without the setting are transparent.

> **Missing assets:** if `Image("profile_icon")` appears in your source but `profile_icon.imageset` is absent from every catalog, `swiftl10n scan` emits a warning before any runtime crash occurs. This diagnostic is produced by the source scan, independently of code generation.

---

### 6. Add `Localizable.xcstrings` for multi-language support

`String(localized:)` reads translations from a **String Catalog** (`.xcstrings`) — the modern replacement for `.strings` files introduced in Xcode 15.

1. **File → New File → String Catalog** — name it exactly `Localizable`
2. Xcode auto-discovers every `String(localized:)` call in your source and populates the catalog — **no manual entry needed**
3. Add a language: Project → Info → Localizations → **+** → select a language
4. The new language column appears in `Localizable.xcstrings` — translate each entry there

`String(localized:)` falls back to the base English string at runtime until a translation exists, so it is safe to ship with an empty catalog.

---

### Using in a UIKit project (no ContentView)

UIKit projects use different entry points but the same `SwiftL10n.scan()` call. No extra configuration — the scanner detects SwiftUI and UIKit strings automatically.

#### What UIKit patterns are detected

| Pattern | Context |
|---|---|
| `label.text = "…"` / `textView.text = "…"` | `.uiLabel` |
| `textField.placeholder = "…"` / `searchBar.placeholder = "…"` | `.uiTextFieldPlaceholder` |
| `navigationItem.title = "…"` / `self.title = "…"` / `title = "…"` | `.uiNavigationTitle` |
| `button.setTitle("…", for: .normal)` | `.uiButtonTitle` |
| `UIAlertController(title: "…", message: "…", …)` | `.uiAlertTitle` + `.uiAlertMessage` |
| `UIAlertAction(title: "…", …)` | `.uiAlertAction` |
| `UIBarButtonItem(title: "…", …)` | `.uiButtonTitle` |
| `UITabBarItem(title: "…", …)` | `.uiTabBarItem` |

#### Option A — `AppDelegate`

```swift
import UIKit
import SwiftL10nCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        let projectPath = "/Users/you/Developer/YourApp/YourApp"  // ← change only this
        Task { _ = try? await SwiftL10n.scan(projectPath: projectPath) }
        #endif
        return true
    }
}
```

#### Option B — `SceneDelegate`

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        #if DEBUG
        let projectPath = "/Users/you/Developer/YourApp/YourApp"  // ← change only this
        Task { _ = try? await SwiftL10n.scan(projectPath: projectPath) }
        #endif
    }
}
```

#### Option C — Root `UIViewController`

```swift
class RootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        let projectPath = "/Users/you/Developer/YourApp/YourApp"  // ← change only this
        Task { _ = try? await SwiftL10n.scan(projectPath: projectPath) }
        #endif
    }
}
```

> **Remove the `SwiftL10n.scan()` call** after your generated files are in Xcode. You only need it when regenerating.
>
> **Sandbox error on iOS?** App Sandbox is macOS-only — iOS has no toggle. Run on **Simulator** (not a real device) and the write will succeed without any settings change.

---

## CLI

Install once, run from the project root:

```bash
git clone https://github.com/GRimAce11/SwiftL10n.git
cd SwiftL10n
swift build -c release
cp .build/release/swiftl10n /usr/local/bin/
```

### Commands

#### `swiftl10n init` — create a config file

```bash
swiftl10n init
```

Writes a commented `.swiftl10n.yml` to the current directory:

```yaml
# SwiftL10n configuration — https://github.com/GRimAce11/SwiftL10n
sources:
  - Sources

output:
  path: Sources/Generated/i18n.swift
  enum_name: i18n
  table_name: Localizable

minimum_confidence: 0.85

exclude: []

incremental: false

assets:
  enabled: false
  path: Sources/Generated/Assets.swift
  enum_name: Assets
```

Options:

```bash
swiftl10n init --sources Sources/App --output App/Generated/i18n.swift
swiftl10n init --min-confidence 0.9
swiftl10n init --force   # overwrite existing .swiftl10n.yml
```

---

#### `swiftl10n scan` — detect strings

With a config file present, run with no arguments:

```bash
swiftl10n scan
```

Or pass a path directly (overrides `sources` in config):

```bash
swiftl10n scan Sources/
```

**Common flags:**

| Flag | Description |
|---|---|
| `--output <path>` | Write generated `i18n.swift` to this path (overrides config) |
| `--assets-output <path>` | Generate `Assets.swift` from `.xcassets` catalogs found in the project root |
| `--min-confidence <0–1>` | Ignore strings below this score (overrides config) |
| `--verbose` | Print every detected string with location, confidence breakdown, and fix suggestion |
| `--quiet` | Suppress all output except errors |
| `--config <path>` | Load config from a specific file instead of auto-discovering |
| `--format json` | Output structured JSON to stdout |
| `--format github` | Emit GitHub Actions `::warning::` annotations (see [GitHub Actions](#github-actions)) |
| `--fail-on warnings` | Exit non-zero on any warning (default: errors only) |
| `--fail-on never` | Always exit 0 (useful for advisory-only CI steps) |
| `--migration-mode audit\|incremental\|strict` | Override migration mode for this run (overrides config) |
| `--dry-run` | Run the full pipeline and print what would be written, but skip all file writes |

**Examples:**

```bash
# Scan and generate, verbose (shows score breakdown + fix suggestions)
swiftl10n scan --verbose --output Sources/Generated/i18n.swift

# CI: fail the build if any warnings are found
swiftl10n scan --fail-on warnings

# CI: strict mode — fail if any hardcoded string exists
swiftl10n scan --migration-mode strict

# Dry run — preview what would be written without touching any files
swiftl10n scan --dry-run

# GitHub Actions annotations
swiftl10n scan --format github

# Structured JSON output — pipe to jq or save as artefact
swiftl10n scan --format json | jq '.scanned'
swiftl10n scan --format json > scan-results.json
```

**JSON output schema:**

```json
{
  "schema_version": "1",
  "swiftl10n_version": "1.0.0",
  "scanned": {
    "files": 5,
    "strings": 42,
    "namespaces": 3,
    "warnings": 1,
    "errors": 0,
    "cache_hits": 4,
    "existing_localized": 18,
    "migration_mode": "incremental",
    "scan_duration_seconds": 0.34,
    "stale_entries_removed": 0,
    "missing_catalog_keys": 2,
    "orphaned_catalog_keys": 0,
    "duplicate_catalog_groups": 1,
    "accessibility_warnings": 3
  },
  "diagnostics": [
    {
      "code": "SL001",
      "severity": "warning",
      "message": "Interpolated string in localizable context — no API will be generated: \"Hello {…}!\"",
      "file": "HomeView.swift",
      "line": 14
    }
  ],
  "namespaces": [
    {
      "name": "Settings",
      "source_file": "SettingsView.swift",
      "strings": [
        {
          "value": "Delete Account",
          "context": "Button",
          "confidence": 0.97,
          "has_interpolation": false,
          "suggested_property_name": "deleteAccountButtonTitle",
          "file": "SettingsView.swift",
          "line": 22,
          "score_explanation": {
            "base": 0.95,
            "factors": [
              { "reason": "multi-word phrase", "delta": 0.02 },
              { "reason": "starts uppercase", "delta": 0.01 },
              { "reason": "title case", "delta": 0.01 }
            ],
            "final": 0.97
          }
        }
      ]
    }
  ]
}
```

---

### CLI configuration (`.swiftl10n.yml`)

When `swiftl10n scan` is run, it looks for `.swiftl10n.yml` by walking up from the current directory. It stops searching when it reaches a project root (`Package.swift`, `.git`, `.xcworkspace`) or your home directory.

All fields are optional — any omitted field uses its default.

```yaml
# Directories to scan, relative to this file.
sources:
  - Sources

# Generated output.
output:
  path: Sources/Generated/i18n.swift
  enum_name: i18n          # root enum name in the generated file
  table_name: Localizable  # .strings table passed to String(localized:)
  merge_strategy: overwrite  # overwrite (default) | region (preserve manual code outside markers)

# Strings below this score are ignored (0.0–1.0).
minimum_confidence: 0.85

# Paths or glob patterns to exclude.
# Supports: exact paths, *.ext, **/pattern
exclude:
  - Sources/Generated
  - "**/*.generated.swift"
  - "**/*.mock.swift"

# Skip re-scanning files whose content hasn't changed.
# Cache is stored at .build/swiftl10n-cache.json.
incremental: true

# Asset code generation.
# Set enabled: true to generate Assets.swift during swiftl10n scan.
assets:
  enabled: false
  path: Sources/Generated/Assets.swift
  enum_name: Assets         # root enum name in the generated file
  # use_image_resource: false  # true → @available(iOS 16, …) ImageResource accessors

# Incremental adoption: tell SwiftL10n about your existing localization system.
# Patterns are prefix-and-boundary matched: "L10n." matches "L10n.save" but not "L10nHelper.save".
existing_localization:
  patterns:
    - "L10n."     # SwiftGen output
    - "Strings."  # custom enum
  exclude_arguments_of:
    - "NSLocalizedString"   # skip string literals inside these functions
    - "String(localized:)"

# Migration mode controls reporting and CI exit behaviour.
#   audit:       (default) report all hardcoded strings — current behavior, zero breaking change
#   incremental: skip already-localized call sites; report only gaps
#   strict:      exit non-zero if any hardcoded string is found (CI enforcement)
migration:
  mode: audit

# Namespace identifier strategy.
#   file:      (default) strip SwiftUI/UIKit suffix from the file name — pre-v0.9 behavior
#   directory: always prefix with the immediate parent directory name
#   auto:      use file strategy when all names are unique; directory-qualified on collision
#              recommended for multi-module projects
namespace_strategy: file

# String Catalog (.xcstrings) validation.
# SwiftL10n automatically finds .xcstrings files under the project root.
# validate_missing: warn when a detected string has no key in the catalog (default: true)
# validate_orphaned: note when a catalog key has no detected source usage (default: false)
string_catalog:
  validate_missing: true
  validate_orphaned: false

# Accessibility audit — flags Image("name") calls missing .accessibilityLabel
# or .accessibilityHidden in the SwiftUI modifier chain.
# Default: false — opt-in to avoid noise in existing codebases.
accessibility_audit:
  enabled: false
```

**CLI flags always override config values.** For example, `swiftl10n scan --min-confidence 0.95` ignores `minimum_confidence` in the config for that run.

---

### Incremental scanning

When `incremental: true` is set, `swiftl10n scan` computes a SHA-256 hash of each file before scanning. If the hash matches the cached value, the file is skipped entirely — no SwiftSyntax parse, no AST walk.

```
Found 42 string(s) across 8 namespace(s) in 23 file(s) (22 cached).
```

The cache is stored at `.build/swiftl10n-cache.json` (already gitignored in SPM projects). It is invalidated automatically when a file changes or when the library version bumps.

---

### Inline suppression

Add `// swiftl10n:ignore` anywhere on a line to silence that line's detection. No configuration needed — it is honoured automatically by every scan.

```swift
let debugLabel = Text("internal_debug_key")  // swiftl10n:ignore
label.text     = "staging_only_banner"       // swiftl10n:ignore — not a UI string
```

A `.note` diagnostic is emitted to confirm the suppression fired:
```
Demo.swift:4:22: note: Suppressed "internal_debug_key" — swiftl10n:ignore
```

Arbitrary text after the marker is allowed (`// swiftl10n:ignore reason here`). Only same-line suppression is supported — the comment must be on the same line as the string literal.

---

### GitHub Actions

`--format github` emits native GitHub Actions annotation syntax, which GitHub renders inline in the diff view of every PR.

```yaml
# .github/workflows/lint.yml
- name: SwiftL10n scan
  run: swiftl10n scan --format github
```

Output per warning:
```
::warning file=Sources/Views/SettingsView.swift,line=42,col=13,title=SwiftL10n::Interpolated string in localizable context — no API will be generated: "Hello {…}!"
```

Summary line:
```
::notice title=SwiftL10n::Found 3 hardcoded string(s) across 2 namespace(s) in 18 file(s)
```

Use with `--migration-mode strict` to fail the PR build when any new hardcoded string is introduced:

```yaml
- name: SwiftL10n strict check
  run: swiftl10n scan --format github --migration-mode strict
```

---

### Xcode Build Phase

Run `swiftl10n scan` automatically on every Xcode build:

1. Select your target → **Build Phases** → **+** → **New Run Script Phase**
2. Drag the new phase **above Compile Sources**
3. Paste the script:

```bash
if which swiftl10n > /dev/null; then
    swiftl10n scan --format github
fi
```

Using `--format github` means detected strings appear inline in the Xcode issue navigator as warnings. The `if which` guard keeps the build clean for team members who haven't installed `swiftl10n` yet.

For CI enforcement, use `--migration-mode strict` and the build will fail if any hardcoded string is introduced:

```bash
if which swiftl10n > /dev/null; then
    swiftl10n scan --format github --migration-mode strict
fi
```

> **Performance:** Enable `incremental: true` in `.swiftl10n.yml` so only changed files are re-scanned on each build. Unchanged files are served from the SHA-256 cache instantly.

---

### Shell Completion

`swiftl10n` ships built-in tab completion for bash, zsh, and fish via ArgumentParser. Generate and install the completion script once:

```bash
# zsh
swiftl10n --generate-completion-script zsh > ~/.zsh/completions/_swiftl10n
# bash
swiftl10n --generate-completion-script bash > /usr/local/etc/bash_completion.d/swiftl10n
# fish
swiftl10n --generate-completion-script fish > ~/.config/fish/completions/swiftl10n.fish
```

After installing, subcommands, flags, and file arguments all tab-complete. The `scan` path argument completes `.swift` files; `--config` completes `.yml`/`.yaml` files.

---

### Verbose output

`--verbose` now shows the confidence score breakdown and the suggested generated property name for each detected string:

```
── SettingsView.swift (2 string(s))
  [Button] "Delete Account"  95% — SettingsView.swift:42:13
      score: +2% multi-word phrase, +1% title case, +1% starts uppercase
      → i18n.<Namespace>.deleteAccountButtonTitle()
  [Text] "Are you sure?"  98% — SettingsView.swift:51:17
      score: +2% multi-word phrase, +2% inside SettingsView (View family), +1% body property
      → i18n.<Namespace>.areYouSure()
```

The suggested property name is also included in `--format json` output under `suggested_property_name`.

---

### ImageResource opt-in

`ImageResource` (iOS 16+, macOS 13+, tvOS 16+, watchOS 9+) provides a typed handle to an asset that can be passed directly to `Image(assetResource)` without a string literal at the call site.

Set `use_image_resource: true` in the `assets:` config section to generate `ImageResource` accessors instead of `Image` functions:

```yaml
assets:
  enabled: true
  use_image_resource: true  # requires iOS 16+ deployment target
```

Generated output with `use_image_resource: true`:
```swift
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public static var profileIcon: ImageResource {
    ImageResource(name: "profile_icon", bundle: .main)
}
```

Generated output with `use_image_resource: false` (default):
```swift
public static func profileIcon() -> Image {
    Image("profile_icon")
}
```

Colors always use `Color("name")` regardless of this setting.

---

## Incremental Adoption

SwiftL10n is designed for real production codebases — not greenfield projects.

Most apps contain a mix of hardcoded strings, partially-adopted localization, legacy patterns, and custom wrappers built over years. SwiftL10n respects all of this. It reports gaps without disrupting what already works.

### Existing Localization Systems

SwiftL10n coexists with any localization system — SwiftGen, R.swift, NSLocalizedString wrappers, CMS-backed systems, or no system at all. Configure the namespaces you already use:

```yaml
existing_localization:
  patterns:
    - "L10n."     # SwiftGen output
    - "i18n."     # SwiftL10n's own generated output
    - "Strings."  # manual enum
  exclude_arguments_of:
    - "NSLocalizedString"
    - "String(localized:)"
```

| Existing system | Pattern to configure |
|---|---|
| SwiftGen | `"L10n."` |
| R.swift | `"R.string.localizable."` |
| Custom enum | `"Strings."`, `"Copy."`, `"Text."` |
| Foundation | add `NSLocalizedString` to `exclude_arguments_of` |
| SwiftL10n own output | `"i18n."` (auto-recognized if configured) |

You can run SwiftL10n alongside any other system indefinitely. There is no migration deadline. Adoption is as gradual as your team wants.

### Migration Modes

```yaml
migration:
  mode: incremental  # audit | incremental | strict
```

| Mode | Behavior | Exit code |
|---|---|---|
| `audit` (default) | Report all hardcoded strings — current behavior | `--fail-on` controlled |
| `incremental` | Recognize existing patterns; report only uncovered gaps | `--fail-on` controlled |
| `strict` | Report all gaps; exit non-zero if any hardcoded string found | Always 1 on any finding |

Override per-run with `--migration-mode incremental`.

### Generated File Merge Strategy

When `merge_strategy: region` is set, SwiftL10n only replaces the content between its ownership markers on each run. Everything outside the markers — manual extensions, documentation, custom helpers — is preserved:

```swift
// MARK: - SwiftL10n Generated BEGIN
public enum i18n {
    // ... regenerated on every run
}
// MARK: - SwiftL10n Generated END

// Manual extensions below — never touched by SwiftL10n
extension i18n.Common {
    static var legacyKey: String { "legacy value" }
}
```

Default (`merge_strategy: overwrite`) replaces the entire file — current behavior, zero breaking change.

### Recommended Migration Workflow

**Phase 0 — Baseline (Day 1, zero risk)**
```bash
swiftl10n scan --format json > baseline.json
cat baseline.json | jq '.summary.totalStrings'
```
Count the scope. Nothing is changed.

**Phase 1 — Configure (Day 1–2)**
```yaml
# .swiftl10n.yml
existing_localization:
  patterns:
    - "L10n."
  exclude_arguments_of:
    - "NSLocalizedString"
migration:
  mode: incremental
```
Re-scan. The reported count drops — now showing only genuine gaps.

**Phase 2 — Generate Missing APIs (Week 1)**
```bash
swiftl10n scan  # generates i18n.swift for detected gaps
```
Review the generated file in a PR. Do not adopt it in source yet — PR is for team review of namespace structure.

**Phase 3 — Adopt Screen by Screen (Weeks 2–N)**
Each migration is a single, human-authored, human-reviewed PR:
```swift
// Before
Text("Delete Account")

// After — manual, developer-owned, reviewed in code review
Text(i18n.Settings.deleteAccount())
```

**Phase 4 — Enforce in CI (Month 2+)**
```yaml
migration:
  mode: strict
```
```bash
# CI step — fails if new hardcoded strings are introduced
swiftl10n scan
```
Prevents regressions. Existing coverage is already recognized and skipped.

**Phase 5 — Decommission Old System (Optional, no deadline)**
Remove the old pattern from `existing_localization.patterns`. New call sites using the old system are now reported as gaps. Migrate them at your own pace.

---

## String Catalog Validation

SwiftL10n cross-references your Swift source against Xcode 15+ String Catalogs (`.xcstrings`) in both directions: it warns when source uses a string absent from the catalog, and notes catalog keys that no source reference was found for.

Both checks run automatically during `swiftl10n scan` when a `.xcstrings` file is found anywhere under the project root. No configuration is needed to get started.

### Configure validation behaviour

```yaml
string_catalog:
  validate_missing: true    # warn when a detected string has no key in the catalog
  validate_orphaned: false  # note when a catalog key has no detected source usage
```

`validate_missing: true` (default) is the most actionable setting: it tells you exactly which strings your code uses that are not yet in the catalog.

`validate_orphaned: false` (default) keeps the report quiet during development when keys legitimately outnumber active source references. Set it to `true` to audit a mature catalog for dead keys before shipping.

### What the diagnostics look like

```
── String Catalog (Localizable.xcstrings · 42 key(s))
   2 missing from catalog:
   ⚠ "Delete Account" — SettingsView.swift:22 [not in catalog]
   ⚠ "Reset Preferences" — SettingsView.swift:31 [not in catalog]
   1 orphaned in catalog:
   ○ "OldFeatureTitle" — key exists in catalog but no source usage found
```

**Missing** means your code has a string that has no localization key in the catalog — it will not be translated when you add a second language. Add the key to the catalog (Xcode auto-discovers `String(localized:)` calls; for hardcoded strings, use the generated `i18n.swift` API).

**Orphaned** means the catalog contains a key the scanner found no source reference for. These are safe to remove once you confirm they are not used by other means (storyboards, server-driven strings, ObjC code).

### Notes

- Interpolated strings (`"Hello {…}!"`) are excluded from missing-key validation — the template value is not a valid catalog key.
- Validation is skipped entirely if no `.xcstrings` file is found, or if the found catalog is empty.
- Multiple catalogs under the project root are merged before validation.

---

## Accessibility Audit

SwiftL10n flags `Image("name")` calls in SwiftUI source that are missing an accessibility modifier in their modifier chain.

### Enable the audit

```yaml
accessibility_audit:
  enabled: true   # default: false — opt in when ready
```

The audit is off by default to avoid noise in codebases not yet using accessibility modifiers. Enable it per-project once your team has adopted the practice.

### What gets flagged

```
⚠ Image literal without accessibility modifier: Image("achievement-badge") — ProfileView.swift:24
⚠ Image literal without accessibility modifier: Image("promo-banner") — ProfileView.swift:29
```

Any `Image("name")` call without one of the following modifiers in the same modifier chain is reported as a `.warning`:

- `.accessibilityLabel(_:)`
- `.accessibilityHidden(_:)`
- `.accessibilityElement(children:)`
- `.accessibilityValue(_:)`
- `.accessibilityIdentifier(_:)`

### What is intentionally excluded

| Call site | Reason |
|---|---|
| `Image(systemName: "…")` | SF Symbol — accessibility defaults are well-defined |
| `Image(decorative: "…")` | Explicitly marked non-semantic |
| `Image("…").accessibilityLabel(…)` | Has modifier — passes |

The check is purely syntactic: it walks the modifier chain in the same scope and stops at the enclosing statement boundary. It does not follow binding expressions or cross-file modifier applications.

---

## Programmatic API

### Primary entry point

```swift
import SwiftL10nCore

// Minimal — both files written to projectPath/Generated/
try await SwiftL10n.scan(projectPath: "/path/to/Sources/YourApp")

// With options
let result = try await SwiftL10n.scan(
    projectPath:       "/path/to/Sources/YourApp",
    stringsOutput:     "/path/to/Sources/YourApp/Generated/i18n.swift",
    assetsOutput:      "/path/to/Sources/YourApp/Generated/Assets.swift",
    minimumConfidence: 0.9,
    generateAssets:    true
)
print("\(result.strings.stringCount) string(s) · \(result.assets?.imageCount ?? 0) image(s)")
```

### Scan a source string (low-level)

```swift
import SwiftL10nCore

let scanner = StringScanner()
let result = scanner.scan(source: sourceCode, filePath: "SettingsView.swift")

for string in result.detectedStrings {
    print("""
    "\(string.value)"
      context:    \(string.context.displayName)
      confidence: \(String(format: "%.2f", string.confidence))
      location:   \(string.location.file):\(string.location.line)
      type:       \(string.enclosingContext.typeName ?? "—")
    """)
}
```

### Scan a file on disk

```swift
let result = try scanner.scan(filePath: "/path/to/SettingsView.swift")
```

### Check diagnostics

```swift
for diagnostic in result.diagnostics {
    print("[\(diagnostic.severity)] \(diagnostic.message)")
}

let warnings     = result.diagnostics.filter { $0.severity == .warning }
let interpolated = result.detectedStrings.filter(\.hasInterpolation)
```

### Run the full pipeline programmatically

`ScanPipeline` is the same engine `swiftl10n scan` uses internally:

```swift
import SwiftL10nCore

let config   = SwiftL10nConfig(sources: ["Sources"], minimumConfidence: 0.85)
let pipeline = ScanPipeline(config: config, baseURL: projectRootURL)
let result   = try await pipeline.run()

print("\(result.totalStrings) strings in \(result.namespaces.count) namespace(s)")
print("\(result.cacheHits) file(s) served from cache")
print("Scanned in \(String(format: "%.2f", result.scanDuration))s · \(result.staleEntriesRemoved) stale cache entries removed")
if result.missingCatalogKeys > 0 {
    print("\(result.missingCatalogKeys) string(s) absent from .xcstrings catalog")
}
if result.accessibilityWarnings > 0 {
    print("\(result.accessibilityWarnings) Image literal(s) missing accessibility modifier")
}

let code = CodeGenerator().generate(namespaces: result.namespaces)
```

### Generate Assets.swift independently

If you need to regenerate `Assets.swift` without a full localization scan — for example after adding new assets — call `generateAssets()` directly:

```swift
import SwiftL10nCore

let result = try await generateAssets(
    sourcesPath: "/path/to/Sources/YourApp",
    outputPath:  "/path/to/Sources/YourApp/Generated/Assets.swift"
)
print("\(result.imageCount) image(s) · \(result.colorCount) color(s) from \(result.catalogCount) catalog(s)")
```

### Asset catalog — parse, validate, generate (low-level)

```swift
import SwiftL10nCore

// 1. Parse all .xcassets bundles under the project root
let catalog = try AssetCatalogParser.parseCatalogs(in: projectRootURL)
print("\(catalog.imageNames.count) image(s), \(catalog.colorNames.count) color(s)")

// 2. Validate source references against the catalog
let assetScanner = AssetScanner()
let refs = try assetScanner.scan(filePath: "HomeView.swift")
let missing = assetScanner.validate(refs, against: catalog)
// missing → [Diagnostic] with .warning for every Image("name") not found in catalog

// 3. Generate Assets.swift from the catalog
let code = AssetCodeGenerator().generate(catalog: catalog)
// write code to Sources/Generated/Assets.swift

// 4. Custom root enum name
let config = AssetCodeGenerator.Configuration(rootEnumName: "R", accessLevel: "internal")
let customCode = AssetCodeGenerator(configuration: config).generate(catalog: catalog)
```

### Namespace inference + localization code generation

```swift
import SwiftL10nCore

let inferrer   = NamespaceInferrer()
let namespaces = inferrer.infer(from: [("SettingsView.swift", result.detectedStrings)])

let output = CodeGenerator().generate(namespaces: namespaces)
print(output)
```

Output:

```swift
extension i18n {
    enum Settings {

        /// "Delete Account"
        static func deleteAccountButtonTitle() -> String {
            String(
                localized: "Delete Account",
                table: General.table,
                bundle: General.bundle,
                comment: "Settings: Button — Delete Account"
            )
        }

    }
}
```

### String Catalog validation

```swift
import SwiftL10nCore
import Foundation

// Parse all .xcstrings files under the project root
let catalog = try StringCatalogParser.parseCatalogs(in: projectRootURL)
print("\(catalog.keys.count) key(s) across \(catalog.languageCount) language(s)")

// Parse a single catalog
let singleCatalog = try StringCatalogParser.parse(url: catalogURL)
print(singleCatalog.contains(key: "Delete Account"))  // true or false

// Cross-reference detected strings against the catalog
let namespaces = NamespaceInferrer().infer(from: fileScanResults)
let validationResult = StringCatalogValidator().validate(namespaces: namespaces, against: catalog)

print("\(validationResult.missingCount) missing from catalog")
for entry in validationResult.missingFromCatalog {
    let loc = entry.locations.first
    print("  \"\(entry.value)\" — \(loc?.file ?? ""):\(loc?.line ?? 0)")
}

print("\(validationResult.orphanedCount) orphaned in catalog")
for key in validationResult.orphanedInCatalog {
    print("  \(key)")
}
```

### Duplicate localization analysis

```swift
import SwiftL10nCore

let analyzer = DuplicateLocalizationAnalyzer()

// Catalog-level: multiple keys sharing the same source-language value
let catalogGroups = analyzer.analyzeCatalog(catalog)
for group in catalogGroups {
    print("Value \"\(group.sharedValue)\" appears under \(group.keys.count) keys: \(group.keys.joined(separator: ", "))")
}

// Namespace-level: same string value appearing in 2+ namespaces (i18n.Common candidates)
let nsGroups = analyzer.analyzeNamespaces(namespaces)
for group in nsGroups {
    let files = group.occurrences.map(\.namespace).joined(separator: ", ")
    print("Value \"\(group.value)\" in \(files) — consider promoting to i18n.Common")
}
```

### Accessibility audit

```swift
import SwiftL10nCore

let auditor = AccessibilityAuditor()
let diagnostics = auditor.audit(source: sourceCode, filePath: "ProfileView.swift")

for warning in diagnostics {
    let location = "\(warning.location?.file ?? ""):\(warning.location.map { "\($0.line)" } ?? "")"
    print("[\(warning.severity)] \(warning.message) — \(location)")
}
// [warning] Image literal without accessibility modifier: Image("achievement-badge") — ProfileView.swift:24
// [warning] Image literal without accessibility modifier: Image("promo-banner") — ProfileView.swift:29
```

---

## Detection rules

### SwiftUI

| Call site | `DetectionContext` | Example |
|---|---|---|
| `Text("…")` | `.textView` | `Text("Hello, World!")` |
| `Button("…") {}` | `.buttonLabel` | `Button("Delete") {}` |
| `Label("…", systemImage:)` | `.labelView` | `Label("Settings", systemImage: "gear")` |
| `Toggle("…", isOn:)` | `.toggle` | `Toggle("Dark Mode", isOn: $enabled)` |
| `TextField("…", text:)` | `.textField` | `TextField("Email", text: $email)` |
| `.navigationTitle("…")` | `.navigationTitle` | `.navigationTitle("Home")` |
| `.navigationBarTitle("…")` | `.navigationTitle` | `.navigationBarTitle("Profile")` |
| `.alert("…", isPresented:)` | `.alert` | `.alert("Are you sure?", isPresented: $shown) {}` |
| `.confirmationDialog("…", isPresented:)` | `.confirmationDialog` | `.confirmationDialog("Choose", isPresented: $shown) {}` |
| `.accessibilityLabel("…")` | `.accessibilityLabel` | `.accessibilityLabel("Close button")` |
| `Section("…") { }` | `.section` | `Section("Account") { … }` |
| `Picker("…", selection:) { }` | `.picker` | `Picker("Sort by", selection: $s) { … }` |
| `Menu("…") { }` | `.menu` | `Menu("More Options") { … }` |
| `DisclosureGroup("…") { }` | `.disclosureGroup` | `DisclosureGroup("Advanced") { … }` |
| `.help("…")` | `.helpText` | `.help("Tap to delete your account")` |

### UIKit — detected automatically alongside SwiftUI

| Call site / assignment | `DetectionContext` | Example |
|---|---|---|
| `label.text = "…"` | `.uiLabel` | `nameLabel.text = "Full Name"` |
| `textView.text = "…"` | `.uiLabel` | `bodyView.text = "Description"` |
| `textField.placeholder = "…"` | `.uiTextFieldPlaceholder` | `emailField.placeholder = "Email"` |
| `searchBar.placeholder = "…"` | `.uiTextFieldPlaceholder` | `searchBar.placeholder = "Search"` |
| `navigationItem.title = "…"` | `.uiNavigationTitle` | `navigationItem.title = "Settings"` |
| `self.title = "…"` / `title = "…"` | `.uiNavigationTitle` | `title = "Profile"` |
| `button.setTitle("…", for:)` | `.uiButtonTitle` | `btn.setTitle("Tap Me", for: .normal)` |
| `UIBarButtonItem(title: "…", …)` | `.uiButtonTitle` | `UIBarButtonItem(title: "Done", …)` |
| `UIAlertController(title: "…", …)` | `.uiAlertTitle` | title argument only |
| `UIAlertController(…, message: "…", …)` | `.uiAlertMessage` | message argument only |
| `UIAlertAction(title: "…", …)` | `.uiAlertAction` | `UIAlertAction(title: "Delete", …)` |
| `UITabBarItem(title: "…", …)` | `.uiTabBarItem` | `UITabBarItem(title: "Home", …)` |

### Intentional exclusions

| Pattern | Example | Reason |
|---|---|---|
| `Text(verbatim:)` | `Text(verbatim: "debug dump")` | Explicit opt-out |
| URLs | `"https://example.com"` | Not UI text |
| File paths | `"/Users/dev/file.txt"` | Not UI text |
| SF Symbol names | `"person.crop.circle"` | Dot-separated lowercase identifier |
| Reverse-DNS keys | `"com.example.app"` | Analytics / bundle ID |
| `snake_case` | `"auth_token"` | Programmatic key |
| `camelCase` | `"viewModelIdentifier"` | Programmatic key |
| `SCREAMING_CASE` | `"FEATURE_FLAG"` | Compile-time constant |
| Interpolated strings | `"Hello \(name)!"` | Detected but flagged; skipped in codegen |

---

## Adding a custom rule

Conform to `DetectionRule` and pass a custom `RuleEngine` to the scanner:

```swift
import SwiftL10nCore
import SwiftSyntax

struct SheetTitleRule: DetectionRule {
    let name = "SheetTitleRule"
    let baseConfidence = 0.90
    let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard node.calledExpression
                .as(MemberAccessExprSyntax.self)?
                .declName.baseName.text == "sheet"
        else { return nil }
        return .unknownUIContext(callee: "sheet")
    }
}

// Add your rule on top of all built-in SwiftUI + UIKit rules
let engine = RuleEngine(
    rules: RuleEngine.default.rules + [SheetTitleRule()],
    assignmentRules: RuleEngine.default.assignmentRules
)
let scanner = StringScanner(ruleEngine: engine)
```

---

## Architecture

```
SwiftL10n/
├── Sources/
│   ├── swiftl10n/                     # CLI executable
│   │   ├── EntryPoint.swift
│   │   ├── Commands/
│   │   │   ├── ScanCommand.swift      # Thin adapter over ScanPipeline
│   │   │   └── InitCommand.swift      # swiftl10n init
│   │   ├── Config/
│   │   │   └── ConfigLoader.swift     # YAML discovery + parsing (Yams)
│   │   └── Output/
│   │       └── JSONReporter.swift     # --format json serialiser
│   └── SwiftL10nCore/                 # Library target
│       ├── Scanner/
│       │   ├── StringScanner.swift        # Entry point — parses + runs pipeline
│       │   ├── DetectionRule.swift        # Protocol + RuleEngine
│       │   ├── Rules/BuiltInRules.swift   # SwiftUI rules
│       │   ├── Rules/UIKitRules.swift     # UIKit rules
│       │   ├── FalsePositiveFilter.swift
│       │   ├── ConfidenceScorer.swift
│       │   └── ContextExtractor.swift
│       ├── Models/
│       │   ├── DetectedString.swift       # Sendable + Codable
│       │   ├── DetectionContext.swift     # Sendable + Codable (custom)
│       │   ├── EnclosingContext.swift     # Sendable + Codable
│       │   ├── Namespace.swift
│       │   └── Diagnostic.swift          # Sendable + Codable
│       ├── Assets/
│       │   ├── AssetCatalog.swift         # AssetCatalog model + AssetCatalogParser
│       │   ├── AssetScanner.swift         # Source-side detection (Image/Color/UIImage/UIColor)
│       │   └── AssetCodeGenerator.swift   # Generates Assets.swift from catalog
│       ├── Config/
│       │   └── SwiftL10nConfig.swift      # Project config model (includes AssetsOutputConfig)
│       ├── Pipeline/
│       │   ├── ScanPipeline.swift         # Reusable scan orchestration
│       │   ├── GlobMatcher.swift          # *, **, ? pattern matching
│       │   └── IncrementalScanCache.swift # CryptoKit SHA-256 cache
│       ├── NamespaceInferrer/
│       ├── CodeGen/
│       │   └── CodeGenerator.swift        # Generates i18n.swift from detected strings
│       ├── StringCatalog/
│       │   ├── StringCatalogParser.swift  # Parses .xcstrings catalogs
│       │   └── StringCatalogValidator.swift # Source ↔ catalog cross-reference
│       ├── Analysis/
│       │   ├── DuplicateLocalizationAnalyzer.swift  # Duplicate key/value detection
│       │   └── AccessibilityAuditor.swift           # Image accessibility completeness
│       ├── Common/
│       │   └── CommonStringExtractor.swift
│       └── Diagnostics/
│           └── DiagnosticsEngine.swift
└── Tests/
    └── SwiftL10nCoreTests/            # 447 tests across 32 files
```

### Detection pipeline

For every `FunctionCallExprSyntax` and `SequenceExprSyntax` (property assignments) in the syntax tree:

1. **Rule matching** — rules are tried in order; UIAlertController matches both its title and message rules
2. **Argument extraction** — `ArgumentSelector.firstUnlabeled` skips opt-out forms like `Text(verbatim:)`
3. **False-positive filtering** — exclusions are applied; a `.note` diagnostic is emitted if filtered
4. **Context extraction** — parent chain is walked to capture enclosing type, property, function
5. **Confidence scoring** — base confidence (per rule) adjusted by content and context deltas
6. **Interpolation handling** — `\(…)` segments replaced with `{…}`, `hasInterpolation` set, `.warning` emitted

---

## Source-Aware Infrastructure Validation

Most iOS code generation tools work in one direction: they read your project's infrastructure — asset catalogs, string tables, storyboards — and generate typed Swift accessors from it. This is useful. SwiftL10n does this too.

The difference is the other direction.

SwiftL10n reads your **source code** and validates it against your **infrastructure**. When your code says `Image("profile_icon")`, SwiftL10n checks whether `profile_icon.imageset` actually exists in your asset catalog. When `SwiftL10n.scan()` runs during development, it scans every `Image(…)`, `Color(…)`, `UIImage(named:)`, and `UIColor(named:)` call alongside the localization scan, cross-references them against every `.xcassets` catalog it finds, and warns about any name that does not exist — before any runtime crash occurs.

| Tool | Catalog → Code | Source → Catalog validation |
|---|---|---|
| SwiftGen | ✓ Typed accessors generated from catalog | ✗ Does not check how source references the catalog |
| R.swift | ✓ Typed accessors generated from catalog | ✗ Does not check how source references the catalog |
| **SwiftL10n** | ✓ Typed accessors generated from catalog | ✓ **Validates source references against catalog** |

SwiftGen and R.swift solve a different problem: they make invalid asset references compile errors by replacing string literals with typed constants. That is a valid and useful approach. SwiftL10n's validation layer solves a different class of failure — the asset reference that compiles fine, passes every test, ships to the App Store, and then silently fails to render because the catalog name was misspelled or the asset was deleted after the typed accessor was written.

The two approaches are complementary. SwiftL10n does not replace SwiftGen or R.swift. It adds a usage-analysis layer that works from the other direction.

The same principle applies to localization: SwiftL10n knows which string keys your code uses and can report which ones are absent from the catalog. Source usage analysis is the layer that existing tooling does not provide.

---

## Current Status

**v1.0.0 — Production stable.**

Two infrastructure domains are active, both with incremental adoption support and resource consistency validation:

| Domain | Status | Generated output |
|---|---|---|
| Localization | Production stable | `i18n.swift` |
| Asset infrastructure | Production stable | `Assets.swift` + missing-asset diagnostics |

**Reliable today:**
- `SwiftL10n.scan(projectPath:)` — single call generates both files and validates assets
- String detection (SwiftUI + UIKit, 20 rules)
- False-positive filtering with documented exclusion reasons
- Confidence scoring (deterministic, 0.0–1.0)
- `i18n.swift` code generation with `String(localized:table:bundle:)` API
- Common string extraction across files (`i18n.Common`)
- Asset catalog parsing (all `.xcassets` structures, namespace groups, `provides-namespace`)
- Missing asset diagnostics (`Image("name")` where `name` is absent from the catalog)
- `Assets.swift` generation — namespace-aware, deterministic, collision-safe, iOS 13+
- iOS / tvOS / watchOS / visionOS compatible (all Apple platforms)
- `.swiftl10n.yml` project config with auto-discovery
- JSON diagnostics output (`--format json`)
- Incremental scan cache (SHA-256 per-file, `.build/swiftl10n-cache.json`)
- **Incremental adoption** — `ExistingLocalizationDetector`, migration modes, `merge_strategy: region`
- **Inline suppression** — `// swiftl10n:ignore` on any line; note diagnostic confirms suppression
- **Confidence explanations** — `--verbose` score breakdown; `suggestedPropertyName` in verbose output and JSON
- **GitHub Actions** — `--format github` emits native `::warning file=…::` annotations
- **`ImageResource`** — `use_image_resource: true` generates `@available(iOS 16, …)` accessors
- **Parallel scanning** — `ScanPipeline.run()` is `async throws`; files scanned concurrently via `withTaskGroup`; results are deterministically sorted
- **Cache hardening** — stale entries (deleted files) pruned on every incremental run; `PipelineResult.staleEntriesRemoved` and `PipelineResult.scanDuration` reported
- **Namespace collision detection** — `NamespaceInferrer.inferDetailed(from:strategy:)` emits `.warning` diagnostics on name collision; `namespace_strategy: file | directory | auto` in config
- **`.xcstrings` catalog validation** — `StringCatalogParser` + `StringCatalogValidator` cross-reference detected strings against Xcode 15+ String Catalogs; missing keys and orphaned translations reported as diagnostics
- **Duplicate localization analysis** — `DuplicateLocalizationAnalyzer` surfaces catalog entries sharing the same value and strings appearing in 2+ namespaces
- **Accessibility audit** — `AccessibilityAuditor` flags `Image("name")` calls missing `.accessibilityLabel` / `.accessibilityHidden`; opt-in via `accessibility_audit.enabled: true`
- 447 tests, 0 failures

---

## Roadmap

SwiftL10n follows a deliberate, phase-gated roadmap. Stability in one phase is a prerequisite for the next. Scope is intentionally narrow — each phase solves one problem well rather than several problems partially.

| Version | Focus | Status |
|---|---|---|
| v0.1 – v0.4.x | Localization infrastructure foundation: SwiftUI + UIKit detection, confidence scoring, false-positive filtering, `i18n.swift` generation | Released |
| v0.5.x | Developer workflow: `.swiftl10n.yml` config, `ScanPipeline`, JSON diagnostics, incremental SHA-256 cache | Released |
| v0.6.0 | Asset infrastructure foundation: `.xcassets` catalog parsing, source-to-catalog cross-reference, missing asset diagnostics | Released |
| v0.6.1 | Asset code generation: namespace-aware `Assets.swift` from catalog | Released |
| v0.6.2 | `SwiftL10n.scan()` unified entry point; `generateAssets()` free function; iOS / tvOS / watchOS compatibility fix | Released |
| v0.7.0 | Incremental adoption infrastructure: `ExistingLocalizationDetector`, `SuppressionIndex`, migration modes (audit/incremental/strict), `merge_strategy: region`, `suggestion` diagnostic severity | Released |
| v0.8.0 | Diagnostics ergonomics: `// swiftl10n:ignore` inline suppression, `ScoreExplanation` + `--verbose` breakdown, `suggestedPropertyName`, `--format github` Actions annotations, `ImageResource` opt-in for iOS 16+ | Released |
| v0.9 | Scale and reliability: parallel file scanning (`withTaskGroup`), incremental cache hardening (stale-entry pruning), `PipelineResult.scanDuration`, namespace collision detection + `NamespaceStrategy` config | Released |
| v1.0 | Resource consistency: `.xcstrings` key existence validation, duplicate localization analysis, accessibility label completeness diagnostics | Released |
| v1.1 | Stability: public API contracts with semantic versioning guarantees, Swift Package Index integration, production-ready CI guides | Planned |

Each phase is additive. APIs released in earlier phases are not removed in later ones without a major version bump.

**What will not appear on this roadmap:** automatic source rewriting, design token inference, generic constants generation, build-time mutations, or any feature that requires semantic type analysis that SwiftSyntax cannot provide. See [Permanent Architectural Boundaries](#permanent-architectural-boundaries).

---

## Why SwiftL10n Never Rewrites Your Source

This is not a limitation. It is an architectural boundary, and the reasoning is worth understanding.

### Namespace inference is a global problem

Replacing `Text("Save")` with a typed call looks straightforward. It is not, because the correct replacement cannot be determined at a single call site:

```swift
// "Save" appears in SettingsView.swift, HomeView.swift, and ProfileView.swift.
// CommonStringExtractor promotes it to i18n.Common.
// The correct replacement everywhere is:
Text(i18n.Common.save())

// But if "Save" only appeared in SettingsView.swift, it would stay in its namespace.
// The correct replacement would be:
Text(i18n.Settings.save())
```

The destination namespace is determined by the **full project scan result** — the set of all other occurrences of the same string, the outcome of common-string extraction, and the file-to-namespace mapping from `NamespaceInferrer`. None of this information is available at a single call site. A tool that rewrites files individually, without the full scan result, generates wrong code. A tool that completes the full scan and then rewrites files is making permanent changes to production source based on analysis the developer has not reviewed.

### Type incompatibility is silent

SwiftUI's `Text` initializer has multiple overloads. One accepts `LocalizedStringKey`; another accepts `String`. The generated `i18n.Settings.save()` returns `String`. These are not interchangeable:

```swift
Text("Save")                     // LocalizedStringKey — integrates with Xcode string extraction
Text(i18n.Settings.save())       // String — different type, different runtime path
```

Replacing one with the other changes the type of the expression without a compiler error. The behavior difference may be subtle — extraction tooling stops seeing the key, runtime fallback behavior changes — and it will not be caught by most test suites. SwiftSyntax cannot determine which overload a call site resolves to without full type information. Full type information requires a running Swift compiler.

Custom view initializers, modifier chains, and function overloads compound this problem. Every call site in every project requires independent semantic verification. This does not reduce to a pattern-matching exercise.

### What SwiftL10n does instead

SwiftL10n generates `i18n.swift` — the complete, correct, type-safe API — and stops there. The developer applies replacements intentionally, one file at a time, using Xcode autocomplete:

1. Run `SwiftL10n.scan(projectPath:)` once, or `swiftl10n scan` from the terminal
2. Drag `Generated/i18n.swift` and `Generated/Assets.swift` into your Xcode project
3. Navigate to a file with hardcoded strings or asset literals
4. Type `i18n.` or `Assets.` where accepted — Xcode autocompletes the namespace and function name
5. The compiler confirms every replacement is type-correct

This takes minutes per file, is verifiably correct at every step, and gives the developer full understanding of every change. The generated API is the scaffolding; the developer is the one who applies it.

---

## Permanent Architectural Boundaries

These constraints are not scheduled features. They are permanent decisions that protect the tool's correctness and the developer's trust.

**No automatic source rewriting.** SwiftL10n reads source; it does not modify it. See [Why SwiftL10n Never Rewrites Your Source](#why-swiftl10n-never-rewrites-your-source).

**No design token inference.** Detecting `.cornerRadius(16)` and suggesting `DesignSystem.cornerRadius.medium` is speculative. The same literal appears in unrelated semantic contexts throughout any real project. Precision is not achievable at scale, and an imprecise design token tool causes more harm than no tool.

**No build-time mutations.** Files are written only when you explicitly call `SwiftL10n.scan()` or run `swiftl10n scan`. SwiftL10n is a development workflow tool. Hidden file modifications during compilation are unacceptable regardless of how useful the modification would be.

**No opaque heuristics.** Every diagnostic has a documented, traceable reason. `FalsePositiveFilter` exclusions are enumerated cases. Confidence scores are additive delta models with documented deltas. Nothing is a black box.

**No generic constants generation.** Typed wrappers for fonts, spacing, and arbitrary project values require a design system contract SwiftL10n does not have. A tool that reaches for problems outside its domain solves none of them reliably.

**No merged infrastructure namespaces.** `i18n.Assets.profileIcon` will never exist. Localization keys and asset names have different runtime semantics, different failure modes, and different generation pipelines. They must remain in separate generated files.

---

## Requirements

| | Minimum |
|---|---|
| Swift | 6.0+ |
| Xcode | 16+ |
| macOS | 13+ |
| iOS | 13+ |
| tvOS | 13+ |
| watchOS | 6+ |
| visionOS | 1+ |

---

## Installation

### `SwiftL10nCore` — library for your app

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftL10nCore", package: "SwiftL10n"),
        ]
    ),
]
```

Or in Xcode: **File → Add Package Dependencies** → enter the URL → tick only **`SwiftL10nCore`**.

### `swiftl10n` — CLI tool

```bash
git clone https://github.com/GRimAce11/SwiftL10n.git
cd SwiftL10n
swift build -c release
cp .build/release/swiftl10n /usr/local/bin/
swiftl10n --version
```

---

## Testing

```bash
swift test
```

447 tests across 32 test files, 0 failures.

| File | What it tests |
|---|---|
| `ScannerTests.swift` | End-to-end scanner behaviour for every rule |
| `DetectionRuleTests.swift` | Each rule in isolation |
| `FalsePositiveFilterTests.swift` | Every exclusion reason + valid pass-throughs |
| `ConfidenceScorerTests.swift` | Scoring deltas, clamping, context boosts |
| `ContextExtractorTests.swift` | struct/class/extension/function/property extraction |
| `InterpolationTests.swift` | Detection, warning, template value, codegen exclusion |
| `FixtureTests.swift` | Integration tests on realistic SwiftUI fixtures |
| `NamespaceInferrerTests.swift` | Suffix stripping, collision handling |
| `DiagnosticsTests.swift` | Severity filtering, formatting |
| `UIKitDetectionTests.swift` | All 12 UIKit patterns |
| `CodeGeneratorTests.swift` | Deduplication, decorator stripping |
| `ConfigTests.swift` | YAML decode, round-trip, defaults, `AssetsOutputConfig` |
| `ConfigLoaderTests.swift` | Discovery walking, load errors, validation |
| `GlobMatcherTests.swift` | `*`, `**`, `?`, edge cases |
| `ScanPipelineTests.swift` | Multi-file scan, exclusion, confidence filter |
| `IncrementalScanCacheTests.swift` | SHA-256 hashing, cache hit/miss, round-trip, integration |
| `AssetCatalogTests.swift` | Parser, namespace groups, appiconset/symbolset skipped, `findCatalogs`, `merged` |
| `AssetScannerTests.swift` | All five call-site forms, `Image(systemName:)` excluded, validation |
| `AssetCodeGeneratorTests.swift` | Identifier/type-name conversion, namespaces, collisions, determinism, config |
| `AssetsGeneratorTests.swift` | `generateAssets()` end-to-end: catalog discovery, output path, parent-dir lookup |
| `InlineSuppressionTests.swift` | `// swiftl10n:ignore` parsing, same-line suppression, scanner integration, UIKit assignment suppression |
| `ConfidenceExplanationTests.swift` | `ScoreExplanation` structure, factor accuracy, verbose summary, `DetectedString` integration, `suggestedPropertyName` |
| `ImageResourceTests.swift` | Config decoding, `@available` annotation, `ImageResource` vs `Image` output, color unaffected, namespace path, round-trip |
| `ExistingLocalizationDetectorTests.swift` | Dot-path reconstruction, boundary-safe pattern matching, call vs member access, suppression locations, real-world fixtures |
| `SuppressionIndexTests.swift` | O(1) lookup, file/line/column precision, merging, integration with detector |
| `MigrationModeTests.swift` | Config decoding, pipeline mode propagation, existing pattern recognition, backwards compatibility |
| `MergeStrategyTests.swift` | Marker replacement, manual code preservation, round-trip stability, config decoding |
| `NamespaceCollisionTests.swift` | Collision detection diagnostics, `.file`/`.auto`/`.directory` strategy behaviour, config decoding, pipeline integration |
| `ParallelScanTests.swift` | Concurrent correctness, deterministic namespace order, `scanDuration` > 0, `staleEntriesRemoved` after file deletion |
| `StringCatalogParserTests.swift` | Key parsing, source value extraction, translation count, comment, language count, missing-localization key fallback, `findCatalogs`, `parseCatalogs`, merge |
| `StringCatalogValidatorTests.swift` | Missing key detection, orphaned key detection, location propagation, interpolated string exclusion, empty catalog skip, cross-namespace deduplication |
| `DuplicateLocalizationTests.swift` | Catalog duplicate groups, unique-value no-flag, sorted output, nil-sourceValue fallback, cross-namespace detection, interpolated exclusion |
| `AccessibilityAuditTests.swift` | Unflagged (with modifier, chain, `systemName:`, `decorative:`), flagged (bare literal, multiple), location accuracy, pipeline integration (default-off, enabled) |

---

## Documentation

| Document | Description |
|---|---|
| [Production Guide](Documentation/ProductionGuide.md) | Step-by-step: install, scan, generate, migrate, CI/CD, custom rules |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to add detection rules and submit PRs |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Example App

`Examples/SwiftL10nDemo/` is a macOS SwiftUI app demonstrating the full API. Open it two ways:

- **Xcode project**: open `Examples/SwiftL10nDemo/SwiftL10nDemo.xcodeproj` directly
- **Swift Package**: open `Examples/SwiftL10nDemo/Package.swift` in Xcode or run `swift run` in that directory

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

SwiftL10n is available under the [MIT License](LICENSE).
