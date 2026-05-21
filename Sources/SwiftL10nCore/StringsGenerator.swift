import Foundation

// MARK: - Top-level convenience function

/// Scans every `.swift` file under `sourcesPath`, generates the `enum i18n { … }` scaffold,
/// and writes it to `outputPath` — all in one call.
///
/// Attach to any view in your project, no extra setup required:
///
/// ```swift
/// .task {
///     let projectPath = "/path/to/Sources/MyApp"   // ← change only this
///     try? await generateStrings(
///         sourcesPath: projectPath,
///         outputPath:  "\(projectPath)/Generated/Strings.swift"
///     )
/// }
/// ```
///
/// - Parameters:
///   - sourcesPath: Folder containing your `.swift` view files (scanned recursively).
///   - outputPath:  Where `Strings.swift` will be written. Parent folder is created if needed.
///   - minimumConfidence: Ignore strings below this score. Default `0.85`.
/// - Returns: Summary — string count, namespace count, warning count, output URL.
@discardableResult
public func generateStrings(
    sourcesPath: String,
    outputPath: String,
    minimumConfidence: Double = 0.85
) async throws -> StringsGenerator.Result {
    try await StringsGenerator(
        sourcesPath: sourcesPath,
        outputPath: outputPath,
        minimumConfidence: minimumConfidence
    ).run()
}

// MARK: -

/// Scans a source directory and writes a `Strings.swift` enum in one call.
///
/// Designed to be called with `await` from any SwiftUI view during development:
///
/// ```swift
/// let result = try await StringsGenerator(
///     sourcesPath: "/path/to/Sources/MyApp",
///     outputPath:  "/path/to/Sources/MyApp/Generated/Strings.swift"
/// ).run()
/// ```
public struct StringsGenerator: Sendable {

    // MARK: - Result

    public struct Result: Sendable {
        /// Total number of localizable strings found across all files.
        public let stringCount: Int
        /// Number of namespace groups inferred from file names.
        public let namespaceCount: Int
        /// Number of interpolated strings that need manual attention.
        public let warningCount: Int
        /// File URL of the written `Strings.swift`.
        public let outputURL: URL
    }

    // MARK: - Errors

    public enum GeneratorError: Error, LocalizedError {
        case sourceDirectoryNotFound(String)
        case permissionDenied(String)

        public var errorDescription: String? {
            switch self {
            case .sourceDirectoryNotFound(let path):
                return "Source directory not found at: \(path)"
            case .permissionDenied(let path):
                return """
                Permission denied — cannot write to: \(path)

                This is caused by the App Sandbox. Fix it with one of these options:

                Option 1 (recommended for dev tools):
                  Xcode → Your Target → Signing & Capabilities
                  → App Sandbox → uncheck "Enable App Sandbox"

                Option 2 (keep sandbox, grant file access):
                  Xcode → Your Target → Signing & Capabilities
                  → App Sandbox → File Access → User Selected Files → Read/Write

                Option 3 (safest — wrap the call so it never runs in production):
                  #if DEBUG
                  Task { await scanStrings() }
                  #endif
                """
            }
        }
    }

    // MARK: - Configuration

    private let sourcesURL: URL
    private let outputURL: URL
    private let minimumConfidence: Double

    // MARK: - Init

    /// - Parameters:
    ///   - sourcesPath: Absolute path to the folder containing your `.swift` view files.
    ///   - outputPath:  Absolute path where `Strings.swift` will be written.
    ///                  The parent directory is created automatically if it does not exist.
    ///   - minimumConfidence: Strings below this threshold are ignored. Default `0.85`.
    public init(
        sourcesPath: String,
        outputPath: String,
        minimumConfidence: Double = 0.85
    ) {
        self.sourcesURL = URL(fileURLWithPath: sourcesPath)
        self.outputURL  = URL(fileURLWithPath: outputPath)
        self.minimumConfidence = minimumConfidence
    }

    // MARK: - Run

    /// Scans every `.swift` file under `sourcesPath`, generates the `enum Strings { … }` scaffold,
    /// writes it to `outputPath`, and returns a summary.
    ///
    /// Runs on a background thread — safe to call with `await` from the main actor.
    public func run() async throws -> Result {
        let copy = self
        return try await Task.detached(priority: .userInitiated) {
            try copy.execute()
        }.value
    }

    // MARK: - Private

    private func execute() throws -> Result {
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw GeneratorError.sourceDirectoryNotFound(sourcesURL.path)
        }

        let scanner = StringScanner(minimumConfidence: minimumConfidence)
        var fileResults: [(String, [DetectedString])] = []
        var warningCount = 0

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let result = scanner.scan(source: source, filePath: url.lastPathComponent)
            warningCount += result.diagnostics.filter { $0.severity == .warning }.count
            guard !result.detectedStrings.isEmpty else { continue }

            // Print every detected string as it is found
            print("── \(url.lastPathComponent) (\(result.detectedStrings.count) string(s))")
            for s in result.detectedStrings {
                let pct  = String(format: "%.0f%%", s.confidence * 100)
                let flag = s.hasInterpolation ? "  ⚠ interpolated — skipped in codegen" : ""
                print("   [\(s.context.displayName)] \"\(s.value)\"  \(pct)\(flag)")
            }

            fileResults.append((url.lastPathComponent, result.detectedStrings))
        }

        // Infer per-file namespaces
        let namespaces = NamespaceInferrer().infer(from: fileResults)

        // Extract strings shared across 2+ namespaces into i18n.Common
        let extraction = CommonStringExtractor().extract(from: namespaces)

        var allNamespaces = extraction.namespaces
        if let common = extraction.common, !common.strings.isEmpty {
            print("\n── Common strings (shared across multiple files → i18n.Common)")
            for s in common.strings {
                let from = extraction.origins[s.value]?.joined(separator: ", ") ?? ""
                print("   \"\(s.value)\"  ← \(from)")
            }
            allNamespaces.insert(common, at: 0)
        }

        let code = CodeGenerator().generate(namespaces: allNamespaces)

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try code.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
               && [NSFileWriteNoPermissionError,
                   NSFileReadNoPermissionError].contains(error.code) {
            throw GeneratorError.permissionDenied(outputURL.path)
        }

        let totalStrings = fileResults.flatMap(\.1).count
        print("\n✓ \(totalStrings) string(s) found · \(allNamespaces.count) namespace(s) · \(warningCount) warning(s)")
        print("✓ Written → \(outputURL.path)")

        return Result(
            stringCount:    totalStrings,
            namespaceCount: allNamespaces.count,
            warningCount:   warningCount,
            outputURL:      outputURL
        )
    }
}
