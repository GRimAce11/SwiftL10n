import Foundation
import Yams
import SwiftL10nCore

/// Discovers, parses, and validates `.swiftl10n.yml` config files.
public struct ConfigLoader: Sendable {

    public static let fileName = ".swiftl10n.yml"

    // Walk upward stops when it hits one of these (project-root indicators).
    private static let rootAnchors = ["Package.swift", ".git", ".xcworkspace", ".xcodeproj"]

    // MARK: - Discovery

    /// Walk up from `startURL` looking for `.swiftl10n.yml`.
    ///
    /// Stops (returns `nil`) when it reaches a project root (Package.swift, .git, etc.)
    /// or the user's home directory — whichever comes first.
    public static func discover(
        from startURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var current = startURL.standardized

        while true {
            let candidate = current.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }

            // Stop at a project root — don't look above it for config
            for anchor in rootAnchors
            where FileManager.default.fileExists(atPath: current.appendingPathComponent(anchor).path) {
                return nil
            }

            // Don't traverse above $HOME
            if current.standardized.path == home.standardized.path { return nil }

            let parent = current.deletingLastPathComponent()
            if parent.standardized.path == current.standardized.path { return nil }
            current = parent
        }
    }

    // MARK: - Loading

    /// Parse a `.swiftl10n.yml` file at `url` into a `SwiftL10nConfig`.
    public static func load(from url: URL) throws -> SwiftL10nConfig {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.fileNotFound(url)
        }

        do {
            return try YAMLDecoder().decode(SwiftL10nConfig.self, from: text)
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Validation

    /// Validate that paths referenced in `config` exist on disk.
    ///
    /// `base` should be the directory that contains `.swiftl10n.yml` so that
    /// relative paths in the config are resolved correctly.
    public static func validate(_ config: SwiftL10nConfig, relativeTo base: URL) throws {
        guard config.minimumConfidence >= 0.0, config.minimumConfidence <= 1.0 else {
            throw ConfigError.validation(
                "minimum_confidence must be between 0.0 and 1.0, got \(config.minimumConfidence)"
            )
        }

        for source in config.sources {
            let resolved = source.hasPrefix("/")
                ? URL(fileURLWithPath: source)
                : base.appendingPathComponent(source)
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw ConfigError.validation("Source path does not exist: \(source)")
            }
        }
    }
}

// MARK: - Errors

public enum ConfigError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case parseError(String)
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Config file not found: \(url.path)"
        case .parseError(let msg):
            return "Failed to parse \(ConfigLoader.fileName): \(msg)"
        case .validation(let msg):
            return "Config validation error: \(msg)"
        }
    }
}
