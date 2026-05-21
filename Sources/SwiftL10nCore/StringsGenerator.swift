import Foundation

// MARK: - Top-level convenience function

/// Scans every `.swift` file under `sourcesPath`, generates the `enum i18n { … }` scaffold,
/// and writes it to `outputPath` — all in one call.
///
/// Attach to any view in your project, no extra setup required:
///
/// ```swift
/// .task {
///     try? await generateStrings(
///         sourcesPath: "/path/to/Sources/MyApp",
///         outputPath:  "/path/to/Sources/MyApp/Generated/Strings.swift"
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

        public var errorDescription: String? {
            switch self {
            case .sourceDirectoryNotFound(let path):
                return "Source directory not found at: \(path)"
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
            fileResults.append((url.lastPathComponent, result.detectedStrings))
        }

        let namespaces = NamespaceInferrer().infer(from: fileResults)
        let code       = CodeGenerator().generate(namespaces: namespaces)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try code.write(to: outputURL, atomically: true, encoding: .utf8)

        return Result(
            stringCount:    fileResults.flatMap(\.1).count,
            namespaceCount: namespaces.count,
            warningCount:   warningCount,
            outputURL:      outputURL
        )
    }
}
