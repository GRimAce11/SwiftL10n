import Foundation
import CryptoKit

// MARK: - ScanCacheEntry

/// A single file's cached scan result.
public struct ScanCacheEntry: Sendable, Codable {
    /// SHA-256 hex digest of the file's byte content.
    public let contentHash: String
    /// Version of `SwiftL10nCore` that produced this entry.
    public let swiftl10nVersion: String
    /// Strings detected when this entry was written.
    public let detectedStrings: [DetectedString]
    /// Diagnostics emitted during the scan that produced this entry.
    public let diagnostics: [Diagnostic]

    public init(
        contentHash: String,
        swiftl10nVersion: String,
        detectedStrings: [DetectedString],
        diagnostics: [Diagnostic]
    ) {
        self.contentHash = contentHash
        self.swiftl10nVersion = swiftl10nVersion
        self.detectedStrings = detectedStrings
        self.diagnostics = diagnostics
    }
}

// MARK: - ScanCache

/// In-memory representation of the scan cache file.
///
/// Keys are resolved (symlink-free) absolute file paths.
/// Stored at `<project>/.build/swiftl10n-cache.json` by default.
public struct ScanCache: Sendable, Codable {

    /// Default location relative to the project root.
    public static let defaultRelativePath = ".build/swiftl10n-cache.json"

    public var entries: [String: ScanCacheEntry]

    public init(entries: [String: ScanCacheEntry] = [:]) {
        self.entries = entries
    }

    /// Returns `true` when `path` has a valid entry matching `hash` and the current library version.
    public func isValid(for path: String, hash: String) -> Bool {
        guard let entry = entries[path] else { return false }
        return entry.contentHash == hash
            && entry.swiftl10nVersion == SwiftL10nCoreVersion.current
    }
}

// MARK: - IncrementalScanCache (I/O + hashing)

/// Loads, saves, and hashes files for the incremental scan cache.
public struct IncrementalScanCache: Sendable {

    // MARK: - I/O

    /// Load a `ScanCache` from `url`.  Throws if the file is missing or malformed.
    public static func load(from url: URL) throws -> ScanCache {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScanCache.self, from: data)
    }

    /// Encode `cache` to JSON and write to `url` atomically.
    /// Creates intermediate directories as needed.
    public static func save(_ cache: ScanCache, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cache)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Hashing

    /// Compute the SHA-256 hex digest of the file at `url`.
    public static func contentHash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256Hex(data)
    }

    /// Compute the SHA-256 hex digest of raw `data`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
