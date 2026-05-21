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

> Add the package, paste the snippet, run it — that's all you need to get your first results.

### 1. Add the dependency

**Xcode:** File → Add Package Dependencies → paste the URL → add `SwiftL10nCore` to your target.

```
https://github.com/GRimAce11/SwiftL10n.git
```

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SwiftL10nCore", package: "SwiftL10n"),
    ]),
]
```

---

### 2. Scan a single view — copy, paste, run

```swift
import SwiftL10nCore

let source = """
import SwiftUI

struct SettingsView: View {
    @State private var notificationsOn = true
    @State private var showAlert = false
    @State private var email = ""

    var body: some View {
        Form {
            TextField("Email address", text: $email)
            Toggle("Push Notifications", isOn: $notificationsOn)
            Button("Delete Account") { showAlert = true }
        }
        .navigationTitle("Settings")
        .alert("Are you sure?", isPresented: $showAlert) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        }
    }
}
"""

let result = StringScanner().scan(source: source, filePath: "SettingsView.swift")

for s in result.detectedStrings {
    let pct = String(format: "%.0f%%", s.confidence * 100)
    print("[\(s.context.displayName)] \"\(s.value)\"  \(pct)  line \(s.location.line)")
}
```

**Output:**

```
[TextField] "Email address"  94%  line 8
[Toggle] "Push Notifications"  95%  line 9
[Button] "Delete Account"  97%  line 10
[navigationTitle] "Settings"  99%  line 13
[alert] "Are you sure?"  96%  line 14
[Button] "Delete"  88%  line 15
[Button] "Cancel"  88%  line 16
```

---

### 3. Scan your whole project — copy, paste, run

```swift
import SwiftL10nCore
import Foundation

let sourcesPath = "/absolute/path/to/YourApp/Sources"  // ← change this

let enumerator = FileManager.default.enumerator(
    at: URL(fileURLWithPath: sourcesPath),
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)!

let scanner = StringScanner(minimumConfidence: 0.85)
var fileResults: [(String, [DetectedString])] = []

for case let url as URL in enumerator where url.pathExtension == "swift" {
    let source = try! String(contentsOf: url)
    let result = scanner.scan(source: source, filePath: url.lastPathComponent)
    if !result.detectedStrings.isEmpty {
        fileResults.append((url.lastPathComponent, result.detectedStrings))
    }
}

let total = fileResults.flatMap(\.1).count
print("Found \(total) strings across \(fileResults.count) files\n")

for (file, strings) in fileResults {
    print("── \(file)")
    for s in strings {
        print("   \"\(s.value)\"  [\(s.context.displayName)]")
    }
}
```

---

### 4. Generate Strings.swift — copy, paste, run

```swift
import SwiftL10nCore
import Foundation

let sourcesPath = "/absolute/path/to/YourApp/Sources"   // ← change this
let outputPath  = "/absolute/path/to/YourApp/Sources/Generated/Strings.swift"  // ← change this

let enumerator = FileManager.default.enumerator(
    at: URL(fileURLWithPath: sourcesPath),
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)!

let scanner = StringScanner(minimumConfidence: 0.85)
var fileResults: [(String, [DetectedString])] = []

for case let url as URL in enumerator where url.pathExtension == "swift" {
    let source = try! String(contentsOf: url)
    let result = scanner.scan(source: source, filePath: url.lastPathComponent)
    if !result.detectedStrings.isEmpty {
        fileResults.append((url.lastPathComponent, result.detectedStrings))
    }
}

let namespaces = NamespaceInferrer().infer(from: fileResults)
let code = CodeGenerator().generate(namespaces: namespaces)

try! FileManager.default.createDirectory(
    atPath: (outputPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true
)
try! code.write(toFile: outputPath, atomically: true, encoding: .utf8)
print("✓ Generated Strings.swift — \(namespaces.count) namespace(s), \(fileResults.flatMap(\.1).count) strings")
```

Add the generated `Strings.swift` to your Xcode target. It looks like this:

```swift
enum Strings {
    enum Settings {
        static let settingsNavigationTitle = NSLocalizedString("Settings", comment: "Settings.settingsNavigationTitle")
        static let deleteAccountButtonTitle = NSLocalizedString("Delete Account", comment: "Settings.deleteAccountButtonTitle")
        static let areYouSureAlertTitle = NSLocalizedString("Are you sure?", comment: "Settings.areYouSureAlertTitle")
    }
    enum Home {
        static let welcomeBack = NSLocalizedString("Welcome Back", comment: "Home.welcomeBack")
    }
}
```

---

### 5. Replace hardcoded strings

```swift
// Before
Text("Welcome Back")
Button("Delete Account") { ... }
.navigationTitle("Settings")
TextField("Email address", text: $email)
Toggle("Push Notifications", isOn: $on)
.alert("Are you sure?", isPresented: $show) { ... }

// After
Text(Strings.Home.welcomeBack)
Button(Strings.Settings.deleteAccountButtonTitle) { ... }
.navigationTitle(Strings.Settings.settingsNavigationTitle)
TextField(Strings.Settings.emailAddressPlaceholder, text: $email)
Toggle(Strings.Settings.pushNotificationsToggleLabel, isOn: $on)
.alert(Strings.Settings.areYouSureAlertTitle, isPresented: $show) { ... }
```

**That's it.** Add a `Localizable.strings` file for each language you support and `NSLocalizedString` handles the rest automatically.

> For CI integration, Xcode Build Phase automation, interpolated strings, and custom rules see the [Production Guide](Documentation/ProductionGuide.md).

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

### Swift Package Manager

Add SwiftL10n to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/SwiftL10n.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftL10nCore", package: "SwiftL10n"),
        ]
    ),
]
```

Or via Xcode: **File → Add Package Dependencies**, enter the repository URL, and add `SwiftL10nCore` to your target.

### CLI (build from source)

```bash
git clone https://github.com/GRimAce11/SwiftL10n.git
cd SwiftL10n
swift build -c release
cp .build/release/swiftl10n /usr/local/bin/
```

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
