# Contributing to SwiftL10n

Thank you for taking the time to contribute. This document covers everything you need to get started.

---

## Table of Contents

- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)
- [Development setup](#development-setup)
- [Running the tests](#running-the-tests)
- [Submitting a pull request](#submitting-a-pull-request)
- [Code style](#code-style)
- [Adding a detection rule](#adding-a-detection-rule)

---

## Reporting bugs

Open an issue using the **Bug Report** template. Please include:

- The Swift source snippet that triggers the wrong behaviour
- What you expected to happen and what actually happened
- Swift toolchain version (`swift --version`) and OS version

---

## Suggesting features

Open an issue using the **Feature Request** template. Describe the SwiftUI call site you'd like detected or the workflow improvement you have in mind.

---

## Development setup

```bash
git clone git@github.com:GRimAce11/SwiftL10n.git
cd SwiftL10n
swift build
swift test
```

Requirements: macOS 14+, Swift 6.0+ (Xcode 16+).

---

## Running the tests

```bash
swift test
```

The test suite has 435 tests split across focused unit-test files and fixture-based integration tests. All tests must pass before a PR can be merged.

To run a single test class:

```bash
swift test --filter ScannerTests
swift test --filter FalsePositiveFilterTests
```

---

## Submitting a pull request

1. Fork the repo and create a branch from `main`.
2. Make your change with tests that cover the new behaviour.
3. Run `swift test` — all 130+ tests must pass.
4. Open a PR against `main` and fill in the pull request template.

---

## Adding catalog / accessibility / analysis features

- **String catalog validation**: extend `StringCatalogValidator` or `StringCatalogParser` in `Sources/SwiftL10nCore/StringCatalog/`.
- **Duplicate / source analysis**: extend `DuplicateLocalizationAnalyzer` in `Sources/SwiftL10nCore/Analysis/`.
- **Accessibility audit rules**: extend `AccessibilityAuditor` (and its `AccessibilityVisitor`) in `Sources/SwiftL10nCore/Analysis/AccessibilityAuditor.swift` — add new node types to `visitPost` and update the accessibility modifier set as needed.

---

## Code style

- **No comments that explain *what* the code does** — well-named identifiers do that.
  Add a comment only when the *why* is non-obvious (hidden constraint, subtle invariant, workaround).
- Swift 6 strict concurrency is enforced at build time. Every new type must be `Sendable`
  or `@unchecked Sendable` with documented thread-safety reasoning.
- No `Foundation` imports in pure logic files — use standard library equivalents.
- Match the surrounding file's style (no blank lines between cases in `switch`, etc.).

---

## Adding a detection rule

1. Add a new `struct` conforming to `DetectionRule` in `Sources/SwiftL10nCore/Scanner/Rules/BuiltInRules.swift`
   (or a new file for large rule families).
2. Add the corresponding case to `DetectionContext` with `displayName` and `propertySuffix`.
3. Register the rule in `RuleEngine.default` inside `DetectionRule.swift`.
4. Add a fixture line to `TestFixtures.allCallSites` in `Tests/SwiftL10nCoreTests/Fixtures.swift`.
5. Add unit tests in `DetectionRuleTests.swift` and update `testDefaultEngineContainsAllBuiltInRules`
   to reflect the new rule count.

Example skeleton:

```swift
// Sources/SwiftL10nCore/Scanner/Rules/BuiltInRules.swift

public struct SheetTitleRule: DetectionRule {
    public let name = "SheetTitleRule"
    public let baseConfidence = 0.90
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard memberName(node) == "sheet" else { return nil }
        return .unknownUIContext(callee: "sheet")
    }
}
```
