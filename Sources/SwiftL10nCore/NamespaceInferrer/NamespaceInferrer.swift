import Foundation

/// Maps per-file scan results to `Namespace` values by deriving a Swift identifier
/// from the source file name.
///
/// Inference rules (applied in order, first match wins):
///   1. Strip known SwiftUI file-name suffixes: `View`, `Screen`, `Page`, `Controller`, `ViewController`.
///   2. Sanitize the remainder into a valid Swift identifier (future phase).
///   3. Fall back to the bare file name (no extension) when no suffix matches.
///
/// Examples:
///   `SettingsView.swift`       → `Settings`
///   `OnboardingScreen.swift`   → `Onboarding`
///   `ProfilePage.swift`        → `Profile`
///   `NetworkManager.swift`     → `NetworkManager`
public struct NamespaceInferrer: Sendable {

    /// Suffixes stripped from file names when building the namespace identifier.
    /// Ordered longest-first so that `ViewController` is tried before `Controller`.
    static let strippableSuffixes = [
        "ViewController",
        "Controller",
        "View",
        "Screen",
        "Page",
    ]

    public init() {}

    // MARK: - Public API

    /// Convert an array of `(filePath, detectedStrings)` pairs into `Namespace` values.
    /// Files with no detected strings are silently dropped — they produce no API surface.
    public func infer(
        from fileResults: [(filePath: String, strings: [DetectedString])]
    ) -> [Namespace] {
        fileResults.compactMap { (filePath, strings) in
            guard !strings.isEmpty else { return nil }
            return Namespace(
                name: namespaceName(for: filePath),
                sourceFile: filePath,
                strings: strings
            )
        }
    }

    // MARK: - Name Derivation

    /// Derives the namespace identifier for a given source file path.
    /// `internal` access so tests can exercise it directly.
    func namespaceName(for filePath: String) -> String {
        let baseName = URL(fileURLWithPath: filePath)
            .deletingPathExtension()
            .lastPathComponent

        for suffix in Self.strippableSuffixes {
            if baseName.hasSuffix(suffix), baseName.count > suffix.count {
                return String(baseName.dropLast(suffix.count))
            }
        }
        return baseName
    }
}
