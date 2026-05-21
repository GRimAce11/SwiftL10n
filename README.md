# SwiftL10n

[![CI](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml/badge.svg)](https://github.com/GRimAce11/SwiftL10n/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%2B%20%7C%20macOS%2013%2B-lightgray.svg)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![SPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

A fast, accurate SwiftUI string scanner that automates the first step of every localization workflow — finding the strings.

---

## Overview

SwiftL10n statically analyses your Swift source using SwiftSyntax and detects every hardcoded string that should be localized. It runs entirely at the source level — no simulator, no SourceKit, no runtime.

Feed it a directory; get back a typed list of detected strings with confidence scores, enclosing context, and a generated `Strings` enum scaffold ready to drop into your project.

---

## Features

- **9 detection rules** out of the box — `Text`, `Button`, `Label`, `Toggle`, `TextField`, `.navigationTitle`, `.alert`, `.confirmationDialog`, `.accessibilityLabel`
- **Smart false-positive prevention** — SF Symbol names, URLs, file paths, reverse-DNS keys, `snake_case`, `camelCase`, and `SCREAMING_CASE` identifiers are all filtered out
- **Confidence scoring** — every result carries a deterministic `0.0–1.0` score adjusted for string content and enclosing SwiftUI context
- **Interpolation awareness** — `Text("Hello \(name)!")` is detected, templated as `"Hello {…}!"`, and flagged with a warning; it is skipped during code generation
- **Enclosing context** — each string records the surrounding type, property, and function
- **Namespace inference** — derives logical namespaces from file names (`SettingsView.swift` → `Settings`)
- **Code generation** — emits a type-safe `enum Strings { enum Settings { … } }` scaffold
- **Extensible** — add custom detection rules by conforming to `DetectionRule`
- **Swift 6 ready** — strict concurrency enforced, fully `Sendable`, zero data races

---

## Quick Start

Add the package, paste the `ContentView` below, change two paths, run — `Strings.swift` is generated automatically.

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
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.1.0"),
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
    do {
        let result = try await generateStrings(
            sourcesPath: "/Users/you/Developer/YourApp/Sources/YourApp",          // ← change
            outputPath:  "/Users/you/Developer/YourApp/Sources/YourApp/Generated/Strings.swift"  // ← change
        )
        print("✓ \(result.stringCount) strings · \(result.namespaceCount) namespace(s) → \(result.outputURL.lastPathComponent)")
    } catch {
        print("SwiftL10n error: \(error.localizedDescription)")
    }
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
✓ Written → .../Sources/YourApp/Generated/Strings.swift
```

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
            └── Strings.swift   ← created automatically
```

**Drag `Generated/Strings.swift` into your Xcode Project Navigator** and tick your app target — done.

---

### 3. What `Generated/Strings.swift` looks like

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

extension i18n {
    enum Home {

        /// "Welcome Back"
        static func welcomeBack() -> String {
            String(
                localized: "Welcome Back",
                table: General.table,
                bundle: General.bundle,
                comment: "Home: Text — Welcome Back"
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

### 5. Add `Localizable.xcstrings` for multi-language support

`String(localized:)` reads translations from a **String Catalog** (`.xcstrings`) — the modern replacement for `.strings` files introduced in Xcode 15.

1. **File → New File → String Catalog** — name it exactly `Localizable`
2. Xcode auto-discovers every `String(localized:)` call in your source and populates the catalog — **no manual entry needed**
3. Add a language: Project → Info → Localizations → **+** → select a language
4. The new language column appears in `Localizable.xcstrings` — translate each entry there

```
Localizable.xcstrings
├── English (Base) — auto-filled from your source code
├── Spanish        — translate here
├── French         — translate here
└── German         — translate here
```

`String(localized:)` falls back to the base English string at runtime until a translation exists, so it is safe to ship with an empty catalog.

---

### Scanning a single file

```swift
let result = StringScanner().scan(
    source: try! String(contentsOfFile: "/path/to/SettingsView.swift"),
    filePath: "SettingsView.swift"
)
result.detectedStrings.forEach { print("[\($0.context.displayName)] \"\($0.value)\"") }
```

---

> Re-run the `ContentView` any time you add new views to regenerate `Strings.swift`.  
> For CI enforcement, Xcode Build Phase automation, and custom rules see the [Production Guide](Documentation/ProductionGuide.md).

---

## Requirements

| Platform | Minimum |
|----------|---------|
| Swift | 6.0+ |
| Xcode | 16+ |
| macOS | 13+ |
| iOS | 13+ |
| tvOS | 13+ |
| watchOS | 6+ |
| visionOS | 1+ |

---

## Installation

This package ships two products. You only ever need one of them depending on how you want to use it.

### `SwiftL10nCore` — library for your app

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftL10nCore", package: "SwiftL10n"),  // ← only this
        ]
    ),
]
```

Or in Xcode: **File → Add Package Dependencies** → enter the URL → when the product picker appears, tick **only `SwiftL10nCore`** and leave `swiftl10n` unticked.

### `swiftl10n` — optional CLI tool (terminal only, never add to an app)

If you prefer to run scans from the terminal instead of calling the API from code:

```bash
git clone https://github.com/GRimAce11/SwiftL10n.git
cd SwiftL10n
swift build -c release
cp .build/release/swiftl10n /usr/local/bin/
```

```bash
swiftl10n scan Sources/ --output Sources/Generated/Strings.swift
```

The CLI is a separate executable that wraps `SwiftL10nCore`. It is never imported into your app — if you see it in Xcode's product picker, leave it unticked.

---

## Usage

### CLI

```bash
# Scan a directory (recursive)
swiftl10n scan Sources/

# Filter noisy output — show only high-confidence strings
swiftl10n scan Sources/ --min-confidence 0.9

# Print every string with its location and context
swiftl10n scan Sources/ --verbose

# Suppress everything except errors
swiftl10n scan Sources/ --quiet
```

Example output:

```
Found 12 localizable string(s) across 3 namespace(s).
  Home: 4 string(s) (HomeView.swift)
  Settings: 6 string(s) (SettingsView.swift)
  Onboarding: 2 string(s) (OnboardingView.swift)
warning: "Hello \(name)!" — Interpolated string; review before localising (SettingsView.swift:14)
```

---

### Programmatic API

#### Scan a source string

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

#### Scan a file on disk

```swift
let result = try scanner.scan(filePath: "/path/to/SettingsView.swift")
```

#### Check for warnings and errors

```swift
for diagnostic in result.diagnostics {
    print("[\(diagnostic.severity)] \(diagnostic.message)")
}

let warnings = result.diagnostics.filter { $0.severity == .warning }
let interpolated = result.detectedStrings.filter(\.hasInterpolation)
```

#### Namespace inference + code generation

```swift
import SwiftL10nCore

let inferrer = NamespaceInferrer()
let namespaces = inferrer.infer(from: [
    ("SettingsView.swift", result.detectedStrings),
])

let output = CodeGenerator().generate(namespaces: namespaces)
print(output)
```

Generated output:

```swift
// Auto-generated by SwiftL10n — do not edit manually.

enum Strings {

    enum Settings {
        /// "Settings"
        static let settingsNavigationTitle = NSLocalizedString(
            "Settings", comment: "Settings.settingsNavigationTitle"
        )
        /// "Profile"
        static let profileLabel = NSLocalizedString(
            "Profile", comment: "Settings.profileLabel"
        )
        /// "Delete Account"
        static let deleteAccountButtonTitle = NSLocalizedString(
            "Delete Account", comment: "Settings.deleteAccountButtonTitle"
        )
    }
}
```

---

## Detection rules

| SwiftUI call | `DetectionContext` | Example |
|---|---|---|
| `Text("…")` | `.textView` | `Text("Hello, World!")` |
| `Button("…") {}` | `.buttonLabel` | `Button("Delete") {}` |
| `Label("…", systemImage:)` | `.labelView` | `Label("Settings", systemImage: "gear")` |
| `Toggle("…", isOn:)` | `.toggle` | `Toggle("Dark Mode", isOn: $enabled)` |
| `TextField("…", text:)` | `.textField` | `TextField("Email", text: $email)` |
| `.navigationTitle("…")` | `.navigationTitle` | `.navigationTitle("Home")` |
| `.navigationBarTitle("…")` | `.navigationTitle` | `.navigationBarTitle("Profile")` (deprecated) |
| `.alert("…", isPresented:)` | `.alert` | `.alert("Are you sure?", isPresented: $shown) {}` |
| `.confirmationDialog("…", isPresented:)` | `.confirmationDialog` | `.confirmationDialog("Choose", isPresented: $shown) {}` |
| `.accessibilityLabel("…")` | `.accessibilityLabel` | `.accessibilityLabel("Close button")` |

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

let engine = RuleEngine(rules: RuleEngine.default.rules + [SheetTitleRule()])
let scanner = StringScanner(ruleEngine: engine)
```

---

## Architecture

```
SwiftL10n/
├── Sources/
│   ├── swiftl10n/                     # CLI executable
│   │   ├── EntryPoint.swift
│   │   └── Commands/ScanCommand.swift
│   └── SwiftL10nCore/                 # Library target
│       ├── Scanner/
│       │   ├── StringScanner.swift        # Entry point — parses + runs pipeline
│       │   ├── DetectionRule.swift        # Protocol + RuleEngine
│       │   ├── Rules/BuiltInRules.swift   # 9 built-in rules
│       │   ├── FalsePositiveFilter.swift  # Deterministic exclusions
│       │   ├── ConfidenceScorer.swift     # 0.0–1.0 scoring
│       │   └── ContextExtractor.swift     # Enclosing type/property/function
│       ├── Models/
│       │   ├── DetectedString.swift
│       │   ├── DetectionContext.swift
│       │   ├── EnclosingContext.swift
│       │   ├── Namespace.swift
│       │   └── Diagnostic.swift
│       ├── NamespaceInferrer/
│       │   └── NamespaceInferrer.swift
│       ├── CodeGen/
│       │   └── CodeGenerator.swift
│       └── Diagnostics/
│           └── DiagnosticsEngine.swift
└── Tests/
    └── SwiftL10nCoreTests/            # 130 tests across 10 files
```

### Detection pipeline

For every `FunctionCallExprSyntax` node in the syntax tree:

1. **Rule matching** — rules are tried in order; first match wins
2. **Argument extraction** — `ArgumentSelector.firstUnlabeled` skips opt-out forms like `Text(verbatim:)`
3. **False-positive filtering** — exclusions are applied; a `.note` diagnostic is emitted if filtered
4. **Context extraction** — parent chain is walked to capture enclosing type, property, function
5. **Confidence scoring** — base confidence (per rule) adjusted by content and context deltas
6. **Interpolation handling** — `\(…)` segments replaced with `{…}`, `hasInterpolation` set, `.warning` emitted

---

## Testing

```bash
swift test
```

The test suite covers:

| File | What it tests |
|---|---|
| `ScannerTests.swift` | End-to-end scanner behaviour for every rule |
| `DetectionRuleTests.swift` | Each rule in isolation via `FunctionCallCollector` |
| `FalsePositiveFilterTests.swift` | Every exclusion reason + valid pass-throughs |
| `ConfidenceScorerTests.swift` | Scoring deltas, clamping, context boosts |
| `ContextExtractorTests.swift` | struct/class/extension/function/property extraction |
| `InterpolationTests.swift` | Detection, warning, template value, codegen exclusion |
| `FixtureTests.swift` | Integration tests on realistic SwiftUI fixtures |
| `NamespaceInferrerTests.swift` | Suffix stripping, collision handling |
| `DiagnosticsTests.swift` | Severity filtering, formatting |

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
