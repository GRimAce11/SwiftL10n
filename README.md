# SwiftL10n

[![CI](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml/badge.svg)](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%2B%20%7C%20macOS%2013%2B-lightgray.svg)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![SPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

A fast, accurate SwiftUI and UIKit string scanner that automates the first step of every localization workflow — finding the strings.

---

## Overview

SwiftL10n statically analyses your Swift source using SwiftSyntax and detects every hardcoded string that should be localized, and every asset name that does not exist in any `.xcassets` catalog. It runs entirely at the source level — no simulator, no SourceKit, no runtime.

Feed it a directory; get back a typed list of detected strings with confidence scores, missing-asset diagnostics, and generated `i18n.swift` / `Assets.swift` scaffolds ready to drop into your project.

---

## Design Philosophy

SwiftL10n is **source-aware infrastructure validation tooling**. The design is governed by six principles that will not change:

**1. Source-driven analysis.** The Swift source file is always the input. SwiftL10n reads your code and validates it against infrastructure (catalogs, string tables). It does not read infrastructure and generate source.

**2. Validation first, generation second.** The primary value is catching errors — `Image("missing_icon")` that will crash at runtime, a localization key used in code that isn't in any `.xcstrings` file. Code generation is a byproduct of the same parsed data, not the primary goal.

**3. Additive generation only.** Generated files (`i18n.swift`, `Assets.swift`) supplement your project. SwiftL10n never rewrites your source, never mutates files during a build, and never modifies infrastructure you own.

**4. Deterministic and explainable.** Same inputs always produce the same outputs. Every diagnostic has a traceable reason. Heuristics are documented. There is no "magic" confidence score — every delta is described in the source.

**5. Trust through precision.** One false positive costs more developer trust than ten missed detections. The FalsePositiveFilter exists for this reason. When uncertain, SwiftL10n stays silent rather than guessing.

**6. Separation of concerns.** Localization infrastructure and asset infrastructure are generated into separate files and through separate pipelines. `i18n.Settings.title()` resolves through the NSBundle translation layer. `Assets.profileIcon()` loads a pixel buffer from the asset catalog. These are different operations and must not share a generated namespace.

---

## Features

- **15 detection rules** out of the box — SwiftUI and UIKit detected automatically, no configuration needed
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
- **Extensible** — add custom detection rules by conforming to `DetectionRule`
- **Swift 6 ready** — strict concurrency enforced, fully `Sendable`, zero data races

---

## Quick Start

Add the package, paste the `ContentView` below, change two paths, run — `i18n.swift` is generated automatically.

### 1. Add the package

**Xcode:** File → Add Package Dependencies → paste the URL:

```
https://github.com/GRimAce11/SwiftL10n.git
```

Xcode shows two products in the picker. **Only add `SwiftL10nCore`:**

| Product | What it is | Add to app? |
|---|---|---|
| `SwiftL10nCore` | The library — all scanning and generation API | **Yes ✓** |
| `swiftl10n` | A CLI terminal tool — not a library | No ✗ |

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.6.1"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SwiftL10nCore", package: "SwiftL10n"),  // ← only this one
    ]),
]
```

---

### 2. Keep your `ContentView` exactly as it is — add two lines

Open your existing `ContentView.swift` and add **one import** and **one `.task` modifier**. Nothing else changes.

```swift
import SwiftUI
import SwiftL10nCore          // ← add this import

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")  // ← your existing view, untouched
            .task { await scanStrings() }  // ← add this one line
    }
}

// ── Paste this function anywhere in your project (same file or separate file) ──

private func scanStrings() async {
    #if DEBUG && !targetEnvironment(simulator) && !os(macOS)
    print("SwiftL10n: skipped — run on Simulator or macOS to generate i18n.swift")
    #elseif DEBUG
    let projectPath = "/Users/you/Developer/YourApp/Sources/YourApp"  // ← change only this

    do {
        let result = try await generateStrings(
            sourcesPath: projectPath,
            outputPath:  "\(projectPath)/Generated/i18n.swift"
        )
        print("✓ \(result.stringCount) strings · \(result.namespaceCount) namespace(s) → \(result.outputURL.lastPathComponent)")
    } catch {
        print("SwiftL10n error: \(error.localizedDescription)")
    }
    #endif
}
```

Run the app once. The Xcode console prints every detected string, highlights shared ones, then confirms the file was written:

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

── ProfileView.swift (2 string(s))
   [Button] "Save"  97%
   [Button] "Edit Profile"  95%

── Common strings (shared across multiple files → i18n.Common)
   "Save"  ← Home, Profile, Settings

✓ 10 string(s) found · 4 namespace(s) · 0 warning(s)
✓ Created → .../Sources/YourApp/Generated/i18n.swift
```

> **Sandbox error?** If you see *"You don't have permission to save the file…"*:
> 1. Xcode → Your Target → **Signing & Capabilities** → **App Sandbox** → untick **Enable App Sandbox**, or
> 2. Keep the sandbox and add **File Access → User Selected Files → Read/Write**
>
> The `#if DEBUG` guard in `scanStrings()` already ensures this code never runs in a release build.

**Remove `.task { await scanStrings() }`** after it runs — you only need it when regenerating.

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
            └── i18n.swift   ← created automatically
```

**Drag `Generated/i18n.swift` into your Xcode Project Navigator** and tick your app target — done.

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

### 5. Generate `Assets.swift` from your catalogs

Enable asset generation in `.swiftl10n.yml`:

```yaml
assets:
  enabled: true
  path: Sources/Generated/Assets.swift
  enum_name: Assets
```

Then run `swiftl10n scan` (or `swiftl10n scan --assets-output Sources/Generated/Assets.swift` for a one-off run). SwiftL10n walks every `.xcassets` bundle it finds, parses the catalog, and emits a typed file:

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

UIKit projects use different entry points but the same `scanStrings()` function. No extra configuration — the scanner detects SwiftUI and UIKit strings automatically.

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

#### Option A — `AppDelegate` (runs once on launch)

```swift
import UIKit
import SwiftL10nCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        Task { await scanStrings() }   // ← add this line

        return true
    }
}

// ── Paste this function anywhere in your project ───────────────────────────
private func scanStrings() async {
    #if DEBUG && !targetEnvironment(simulator) && !os(macOS)
    print("SwiftL10n: skipped — run on Simulator or macOS to generate i18n.swift")
    #elseif DEBUG
    let projectPath = "/Users/you/Developer/YourApp/YourApp"  // ← change only this

    do {
        let result = try await generateStrings(
            sourcesPath: projectPath,
            outputPath:  "\(projectPath)/Generated/i18n.swift"
        )
        print("✓ \(result.stringCount) strings · \(result.namespaceCount) namespace(s) → \(result.outputURL.lastPathComponent)")
    } catch {
        print("SwiftL10n error: \(error.localizedDescription)")
    }
    #endif
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
        Task { await scanStrings() }   // ← add this line
    }
}
```

#### Option C — Root `UIViewController`

```swift
class RootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await scanStrings() }   // ← add this line
    }
}
```

> **Remove the `Task { await scanStrings() }` line** after `i18n.swift` is generated.
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
| `--verbose` | Print every detected string with location and context |
| `--quiet` | Suppress all output except errors |
| `--config <path>` | Load config from a specific file instead of auto-discovering |
| `--format json` | Output structured JSON to stdout instead of console text |
| `--fail-on warnings` | Exit non-zero on any warning (default: errors only) |
| `--fail-on never` | Always exit 0 (useful for advisory-only CI steps) |

**Examples:**

```bash
# Scan and generate, verbose
swiftl10n scan --verbose --output Sources/Generated/i18n.swift

# CI: fail the build if any warnings are found
swiftl10n scan --fail-on warnings

# Structured JSON output — pipe to jq or save as artefact
swiftl10n scan --format json | jq '.scanned'
swiftl10n scan --format json > scan-results.json
```

**JSON output schema:**

```json
{
  "schema_version": "1",
  "swiftl10n_version": "0.6.1",
  "scanned": {
    "files": 5,
    "strings": 42,
    "namespaces": 3,
    "warnings": 1,
    "errors": 0,
    "cache_hits": 4
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
          "file": "SettingsView.swift",
          "line": 22
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
  enum_name: Assets     # root enum name in the generated file
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

## Programmatic API

### Scan a source string

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
let result   = try pipeline.run()

print("\(result.totalStrings) strings in \(result.namespaces.count) namespace(s)")
print("\(result.cacheHits) file(s) served from cache")

let code = CodeGenerator().generate(namespaces: result.namespaces)
```

### Asset catalog — parse, validate, generate

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
│       ├── Common/
│       │   └── CommonStringExtractor.swift
│       └── Diagnostics/
│           └── DiagnosticsEngine.swift
└── Tests/
    └── SwiftL10nCoreTests/            # 282 tests across 18 files
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

## Current Status

**v0.6.1 — Production stable.**

Two infrastructure domains are active:

| Domain | Status | Generated output |
|---|---|---|
| Localization | Production stable | `i18n.swift` |
| Asset infrastructure | Production stable | `Assets.swift` + missing-asset diagnostics |

**Reliable today:**
- String detection (SwiftUI + UIKit, 15 rules)
- False-positive filtering with documented exclusion reasons
- Confidence scoring (deterministic, 0.0–1.0)
- `i18n.swift` code generation with `String(localized:table:bundle:)` API
- Common string extraction across files (`i18n.Common`)
- Asset catalog parsing (all `.xcassets` structures, namespace groups, `provides-namespace`)
- Missing asset diagnostics (`Image("name")` where `name` is absent from the catalog)
- `Assets.swift` generation — namespace-aware, deterministic, collision-safe, iOS 13+
- `.swiftl10n.yml` project config with auto-discovery
- JSON diagnostics output (`--format json`)
- Incremental scan cache (SHA-256 per-file, `.build/swiftl10n-cache.json`)
- 282 tests, 0 failures

---

## Roadmap

SwiftL10n follows a deliberate, phase-gated roadmap. Each phase must be proven stable before the next begins.

| Version | Theme | Status |
|---|---|---|
| v0.1 – v0.4.x | Localization scanning, UIKit + SwiftUI detection, confidence scoring, code generation | Released |
| v0.5.x | Config files, ScanPipeline, JSON output, incremental cache, GlobMatcher | Released |
| v0.6.0 | Asset catalog parsing, source-to-catalog validation, missing asset diagnostics | Released |
| v0.6.1 | Typed `Assets.swift` generation — namespace-aware, deterministic, validated against catalog | Released |
| v0.7 | Diagnostics ergonomics: inline suppression, fix suggestions, confidence explanations, GitHub Actions output | Planned |
| v0.8 | Performance: large-project benchmarking, parallel scanning, incremental cache hardening, multi-module support | Planned |
| v0.9 | Resource consistency: accessibility diagnostics, duplicate localization analysis, `.xcstrings` key validation | Planned |
| v1.0 | Stable public API contracts, semantic versioning guarantees, Swift Package Index integration | Planned |

Phases are additive. Nothing released in an earlier phase is removed or broken in a later one.

---

## What SwiftL10n Will Never Do

These are permanent boundaries. They exist because violating them would compromise the tool's reliability and developer trust.

**Never rewrite your source code.** SwiftL10n reads source; it does not modify it. Any feature that would change a `.swift` file automatically — even with a preview — is out of scope. The tool has no type information and no semantic understanding of your business logic. Automated source mutation without type information produces incorrect code.

**Never infer design tokens from magic numbers.** Detecting `.cornerRadius(16)` and suggesting a `DesignSystem.cornerRadius.medium` constant is speculative. The same literal appears in completely different semantic contexts. False-positive rates would be too high to be useful and too high to be trusted.

**Never generate from speculative heuristics.** Every generated identifier — localization function, asset accessor — is derived from a concrete, existing artifact: a detected string literal or a named asset in a catalog. Nothing is invented.

**Never mutate files during a build phase.** Writing to disk only happens when you explicitly run `swiftl10n scan`. SwiftL10n is a development tool, not a build system plugin that silently modifies files mid-compile.

**Never become a generic constants generator.** Typed wrappers for colors, fonts, spacing, and other design tokens are legitimate problems, but they require a design system contract that SwiftL10n does not have access to. A tool that tries to solve every project infrastructure problem solves none of them well.

**Never merge localization and asset namespaces.** `i18n.Assets.profileIcon` will never exist. Localization keys resolve through the translation layer at runtime; asset names load pixel buffers from the catalog. They are different operations with different failure modes and must remain in separate generated files.

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
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.6.1"),
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
