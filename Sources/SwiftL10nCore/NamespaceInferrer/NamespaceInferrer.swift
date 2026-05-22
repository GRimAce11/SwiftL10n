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

    // MARK: - Constants

    /// Suffixes stripped from file names when building the namespace identifier.
    /// Ordered longest-first so that `ViewController` is tried before `Controller`.
    static let strippableSuffixes = [
        "ViewController",
        "Controller",
        "View",
        "Screen",
        "Page",
    ]

    /// Directory names too generic to use as namespace prefixes.
    private static let genericDirectories: Set<String> = [
        "Sources", "Source", "src", "SwiftUI", "UIKit",
        "Views", "Screens", "Pages", "Controllers",
        "Features", "Modules", "App", "Main",
    ]

    public init() {}

    // MARK: - Public API

    /// Convert an array of `(filePath, detectedStrings)` pairs into `Namespace` values.
    /// Files with no detected strings are silently dropped.
    ///
    /// This is the backward-compatible entry point — uses `.file` strategy, returns only namespaces.
    public func infer(
        from fileResults: [(filePath: String, strings: [DetectedString])]
    ) -> [Namespace] {
        inferDetailed(from: fileResults, strategy: .file).namespaces
    }

    /// Full inference with collision detection and configurable strategy.
    ///
    /// - Returns: An `InferenceResult` containing the final namespaces and any collision diagnostics.
    public func inferDetailed(
        from fileResults: [(filePath: String, strings: [DetectedString])],
        strategy: SwiftL10nConfig.NamespaceStrategy = .file
    ) -> InferenceResult {
        let candidates = fileResults.filter { !$0.strings.isEmpty }
        guard !candidates.isEmpty else { return InferenceResult(namespaces: [], collisionDiagnostics: []) }

        // First pass: compute raw names
        var rawNames: [String: [String]] = [:]  // rawName → [filePaths]
        for (filePath, _) in candidates {
            let name = namespaceName(for: filePath)
            rawNames[name, default: []].append(filePath)
        }

        // Detect collisions
        let collisions = rawNames.filter { $0.value.count > 1 }
        var diagnostics: [Diagnostic] = []
        for (name, paths) in collisions.sorted(by: { $0.key < $1.key }) {
            let fileNames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            diagnostics.append(Diagnostic(
                severity: .warning,
                message: "Namespace collision: \(paths.count) files infer to \"\(name)\" (\(fileNames)). "
                    + "Set namespace_strategy: auto in config to disambiguate automatically."
            ))
        }

        // Build final namespaces
        var namespaces: [Namespace] = []
        for (filePath, strings) in candidates {
            let rawName = namespaceName(for: filePath)
            let isCollision = (rawNames[rawName]?.count ?? 1) > 1

            let finalName: String
            switch strategy {
            case .file:
                finalName = rawName  // preserve collision — generate will emit duplicate extensions
            case .directory:
                finalName = directoryQualifiedName(for: filePath, base: rawName)
            case .auto:
                finalName = isCollision
                    ? directoryQualifiedName(for: filePath, base: rawName)
                    : rawName
            }

            namespaces.append(Namespace(name: finalName, sourceFile: filePath, strings: strings))
        }

        return InferenceResult(namespaces: namespaces, collisionDiagnostics: diagnostics)
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

    /// Prefix `base` with the immediate parent directory name when it is meaningful.
    /// Returns `base` unchanged when the parent is empty, `.`, or in the generic-directory list.
    private func directoryQualifiedName(for filePath: String, base: String) -> String {
        let url    = URL(fileURLWithPath: filePath)
        let parent = url.deletingLastPathComponent().lastPathComponent

        guard !parent.isEmpty, parent != ".", !Self.genericDirectories.contains(parent) else {
            return base
        }

        let capitalised = parent.prefix(1).uppercased() + parent.dropFirst()
        return capitalised + base
    }
}

// MARK: - InferenceResult

extension NamespaceInferrer {
    /// The full output of a `inferDetailed(from:strategy:)` call.
    public struct InferenceResult: Sendable {
        /// Final resolved namespaces (de-duplicated or disambiguated as needed).
        public let namespaces: [Namespace]
        /// Warning diagnostics emitted for each namespace collision detected.
        public let collisionDiagnostics: [Diagnostic]
    }
}
