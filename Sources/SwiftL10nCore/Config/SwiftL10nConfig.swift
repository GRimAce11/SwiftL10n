import Foundation

/// Project-level configuration for SwiftL10n.
///
/// Loaded from `.swiftl10n.yml` at the project root. CLI flags always override
/// the values read here.  Use `swiftl10n init` to generate a starter file.
public struct SwiftL10nConfig: Sendable, Codable, Equatable {

    // MARK: - Top-level fields

    /// Directories to scan, relative to the config file's directory. Default: `["Sources"]`.
    public let sources: [String]
    /// Localization code-generation output settings.
    public let output: OutputConfig
    /// Ignore strings scored below this threshold. Default: `0.85`.
    public let minimumConfidence: Double
    /// Paths or glob patterns to exclude. Example: `["Sources/Generated", "**/*.generated.swift"]`.
    public let exclude: [String]
    /// Cache per-file scan results to speed up subsequent runs. Default: `false`.
    public let incremental: Bool
    /// Asset code-generation settings. Set `enabled: true` to generate `Assets.swift`.
    public let assets: AssetsOutputConfig
    /// Existing localization system detection. Patterns recognized and excluded from gap reporting.
    public let existingLocalization: ExistingLocalizationConfig
    /// Incremental adoption migration mode. Default: `audit` (current behavior unchanged).
    public let migration: MigrationConfig
    /// Controls how namespace identifiers are derived from source file paths.
    /// Default: `file` — strip SwiftUI suffix from the file name (pre-v0.9 behavior).
    public let namespaceStrategy: NamespaceStrategy

    // MARK: - Nested: NamespaceStrategy

    /// Controls how namespace identifiers are derived from source file names.
    public enum NamespaceStrategy: String, Sendable, Codable, Equatable {
        /// (Default) Strip the SwiftUI/UIKit suffix from the file name.
        /// `SettingsView.swift` → `Settings`. Pre-v0.9 behavior.
        case file
        /// Always prefix with the parent directory name.
        /// `Payment/SettingsView.swift` → `PaymentSettings`.
        case directory
        /// `file` when all names are unique; `directory`-qualified when a collision is detected.
        /// Recommended for multi-module projects.
        case auto
    }

    // MARK: - Nested: ExistingLocalizationConfig

    /// Detection config for existing localization systems (SwiftGen, NSLocalizedString, custom wrappers).
    public struct ExistingLocalizationConfig: Sendable, Codable, Equatable {
        /// Namespace root patterns to recognize as already-localized call sites.
        /// Trailing dot optional: `"L10n."` and `"L10n"` are treated identically.
        public let patterns: [String]
        /// Function names whose string literal arguments are excluded from gap reporting.
        public let excludeArgumentsOf: [String]

        public init(patterns: [String] = [], excludeArgumentsOf: [String] = []) {
            self.patterns           = patterns
            self.excludeArgumentsOf = excludeArgumentsOf
        }

        public static let `default` = ExistingLocalizationConfig()

        /// `true` when at least one pattern or exclusion is configured.
        public var isActive: Bool { !patterns.isEmpty || !excludeArgumentsOf.isEmpty }

        /// Converts to the detector's own `Config` type.
        public var detectorConfig: ExistingLocalizationDetector.Config {
            .init(patterns: patterns, excludeArgumentsOf: excludeArgumentsOf)
        }

        enum CodingKeys: String, CodingKey {
            case patterns
            case excludeArgumentsOf = "exclude_arguments_of"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            patterns           = try c.decodeIfPresent([String].self, forKey: .patterns)           ?? []
            excludeArgumentsOf = try c.decodeIfPresent([String].self, forKey: .excludeArgumentsOf) ?? []
        }
    }

    // MARK: - Nested: MigrationConfig

    /// Controls how SwiftL10n behaves in the presence of existing localization systems.
    public struct MigrationConfig: Sendable, Codable, Equatable {
        public enum Mode: String, Sendable, Codable, Equatable {
            /// (Default) Report all hardcoded strings. Zero behavior change from v0.6.x.
            case audit
            /// Skip already-localized call sites; report only gaps.
            case incremental
            /// Exit non-zero if any hardcoded string is found (CI enforcement).
            case strict
        }

        public let mode: Mode

        public init(mode: Mode = .audit) {
            self.mode = mode
        }

        public static let `default` = MigrationConfig()

        enum CodingKeys: String, CodingKey { case mode }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .audit
        }
    }

    // MARK: - Nested: AssetsOutputConfig

    public struct AssetsOutputConfig: Sendable, Codable, Equatable {
        /// Whether to generate `Assets.swift` during `swiftl10n scan`. Default: `false`.
        public let enabled: Bool
        /// Where to write `Assets.swift`, relative to the config file's directory.
        public let path: String
        /// Root enum name in the generated file. Default: `Assets`.
        public let enumName: String
        /// Generate `ImageResource` accessors (iOS 16+) instead of `Image` for image assets.
        /// Requires deployment target iOS 16+ / macOS 13+ / tvOS 16+ / watchOS 9+. Default: `false`.
        public let useImageResource: Bool

        public init(
            enabled: Bool = false,
            path: String = "Sources/Generated/Assets.swift",
            enumName: String = "Assets",
            useImageResource: Bool = false
        ) {
            self.enabled          = enabled
            self.path             = path
            self.enumName         = enumName
            self.useImageResource = useImageResource
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case path
            case enumName        = "enum_name"
            case useImageResource = "use_image_resource"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled          = try c.decodeIfPresent(Bool.self,   forKey: .enabled)          ?? false
            path             = try c.decodeIfPresent(String.self, forKey: .path)             ?? "Sources/Generated/Assets.swift"
            enumName         = try c.decodeIfPresent(String.self, forKey: .enumName)         ?? "Assets"
            useImageResource = try c.decodeIfPresent(Bool.self,   forKey: .useImageResource) ?? false
        }
    }

    // MARK: - Nested: OutputConfig

    public struct OutputConfig: Sendable, Codable, Equatable {
        /// Where to write `i18n.swift`, relative to the config file's directory.
        public let path: String
        /// Root enum name in the generated file. Default: `i18n`.
        public let enumName: String
        /// `.strings` table name passed to `String(localized:table:)`. Default: `Localizable`.
        public let tableName: String
        /// File write strategy. `overwrite` (default) replaces the whole file each run.
        /// `region` replaces only the generated block between ownership markers, preserving
        /// manual extensions above and below.
        public let mergeStrategy: MergeStrategy

        public enum MergeStrategy: String, Sendable, Codable, Equatable {
            case overwrite  // default: full-file replacement (current behavior)
            case region     // marker-bounded replacement only
        }

        public init(
            path: String = "Sources/Generated/i18n.swift",
            enumName: String = "i18n",
            tableName: String = "Localizable",
            mergeStrategy: MergeStrategy = .overwrite
        ) {
            self.path          = path
            self.enumName      = enumName
            self.tableName     = tableName
            self.mergeStrategy = mergeStrategy
        }

        enum CodingKeys: String, CodingKey {
            case path
            case enumName      = "enum_name"
            case tableName     = "table_name"
            case mergeStrategy = "merge_strategy"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path          = try c.decodeIfPresent(String.self,          forKey: .path)          ?? "Sources/Generated/i18n.swift"
            enumName      = try c.decodeIfPresent(String.self,          forKey: .enumName)      ?? "i18n"
            tableName     = try c.decodeIfPresent(String.self,          forKey: .tableName)     ?? "Localizable"
            mergeStrategy = try c.decodeIfPresent(MergeStrategy.self,   forKey: .mergeStrategy) ?? .overwrite
        }
    }

    // MARK: - Default

    public static let `default` = SwiftL10nConfig(
        sources: ["Sources"],
        output: .init(),
        minimumConfidence: 0.85,
        exclude: [],
        incremental: false,
        assets: .init(),
        existingLocalization: .default,
        migration: .default,
        namespaceStrategy: .file
    )

    // MARK: - Init

    public init(
        sources: [String] = ["Sources"],
        output: OutputConfig = .init(),
        minimumConfidence: Double = 0.85,
        exclude: [String] = [],
        incremental: Bool = false,
        assets: AssetsOutputConfig = .init(),
        existingLocalization: ExistingLocalizationConfig = .default,
        migration: MigrationConfig = .default,
        namespaceStrategy: NamespaceStrategy = .file
    ) {
        self.sources              = sources
        self.output               = output
        self.minimumConfidence    = minimumConfidence
        self.exclude              = exclude
        self.incremental          = incremental
        self.assets               = assets
        self.existingLocalization = existingLocalization
        self.migration            = migration
        self.namespaceStrategy    = namespaceStrategy
    }

    // MARK: - CodingKeys (snake_case YAML ↔ camelCase Swift)

    enum CodingKeys: String, CodingKey {
        case sources
        case output
        case minimumConfidence    = "minimum_confidence"
        case exclude
        case incremental
        case assets
        case existingLocalization = "existing_localization"
        case migration
        case namespaceStrategy    = "namespace_strategy"
    }

    // Provide defaults for every field so a minimal YAML (e.g. `sources: [Sources]`) is valid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources              = try c.decodeIfPresent([String].self,               forKey: .sources)              ?? ["Sources"]
        output               = try c.decodeIfPresent(OutputConfig.self,           forKey: .output)               ?? .init()
        minimumConfidence    = try c.decodeIfPresent(Double.self,                 forKey: .minimumConfidence)    ?? 0.85
        exclude              = try c.decodeIfPresent([String].self,               forKey: .exclude)              ?? []
        incremental          = try c.decodeIfPresent(Bool.self,                   forKey: .incremental)          ?? false
        assets               = try c.decodeIfPresent(AssetsOutputConfig.self,     forKey: .assets)               ?? .init()
        existingLocalization = try c.decodeIfPresent(ExistingLocalizationConfig.self, forKey: .existingLocalization) ?? .default
        migration            = try c.decodeIfPresent(MigrationConfig.self,        forKey: .migration)            ?? .default
        namespaceStrategy    = try c.decodeIfPresent(NamespaceStrategy.self,      forKey: .namespaceStrategy)    ?? .file
    }
}
