import Foundation

/// A parsed view of one or more Xcode 15+ `.xcstrings` String Catalog files.
public struct StringCatalog: Sendable {

    /// The source language code (`"en"`, `"fr"`, etc.).
    public let sourceLanguage: String

    /// All entries, keyed by localization key.
    public let entries: [String: Entry]

    /// The catalog URL this was parsed from. `nil` for merged or empty catalogs.
    public let catalogURL: URL?

    public struct Entry: Sendable {
        /// Developer comment on the key.
        public let comment: String?
        /// Source-language value. When the catalog has no localization for the source language,
        /// this falls back to the key itself (how Xcode handles auto-extracted strings).
        public let sourceValue: String?
        /// Number of languages that have a translation for this key.
        public let translationCount: Int
    }

    // MARK: - Derived

    public var keys: Set<String> { Set(entries.keys) }

    /// Maximum translation count across all entries — approximates the number of languages.
    public var languageCount: Int { entries.values.map(\.translationCount).max() ?? 0 }

    public func contains(key: String) -> Bool { entries[key] != nil }

    // MARK: - Merge

    public func merged(_ other: StringCatalog) -> StringCatalog {
        var combined = entries
        for (k, v) in other.entries { combined[k] = v }
        return StringCatalog(
            sourceLanguage: sourceLanguage,
            entries: combined,
            catalogURL: catalogURL ?? other.catalogURL
        )
    }

    // MARK: - Empty

    public static let empty = StringCatalog(sourceLanguage: "en", entries: [:], catalogURL: nil)
}

/// Parses `.xcstrings` String Catalog files produced by Xcode 15+.
public struct StringCatalogParser: Sendable {

    public init() {}

    // MARK: - Public API

    /// Recursively finds all `.xcstrings` files under `directory`.
    /// Does not recurse into hidden directories or package descendants.
    public static func findCatalogs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "xcstrings" {
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// Parses and merges every `.xcstrings` catalog found recursively under `directory`.
    /// Returns `StringCatalog.empty` when no catalogs are found.
    public static func parseCatalogs(in directory: URL) throws -> StringCatalog {
        let urls = try findCatalogs(in: directory)
        guard !urls.isEmpty else { return .empty }
        return try urls
            .map { try parse(url: $0) }
            .reduce(.empty) { $0.merged($1) }
    }

    /// Parses a single `.xcstrings` file.
    public static func parse(url: URL) throws -> StringCatalog {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(XCStringsFile.self, from: data)

        var entries: [String: StringCatalog.Entry] = [:]
        for (key, stringEntry) in file.strings {
            let sourceValue = stringEntry.localizations?[file.sourceLanguage]?.stringUnit?.value
                ?? (stringEntry.localizations == nil ? key : nil)
            let translationCount = stringEntry.localizations?.count ?? 0
            entries[key] = StringCatalog.Entry(
                comment: stringEntry.comment,
                sourceValue: sourceValue,
                translationCount: translationCount
            )
        }

        return StringCatalog(
            sourceLanguage: file.sourceLanguage,
            entries: entries,
            catalogURL: url
        )
    }
}

// MARK: - Internal JSON model

private struct XCStringsFile: Codable {
    let sourceLanguage: String
    let strings: [String: StringEntry]

    struct StringEntry: Codable {
        let comment: String?
        let localizations: [String: Localization]?

        enum CodingKeys: String, CodingKey { case comment, localizations }
    }

    struct Localization: Codable {
        let stringUnit: StringUnit?
        // plural variations intentionally not modelled — key presence is what matters
        enum CodingKeys: String, CodingKey { case stringUnit }
    }

    struct StringUnit: Codable {
        let state: String
        let value: String
    }

    enum CodingKeys: String, CodingKey { case sourceLanguage, strings }
}
