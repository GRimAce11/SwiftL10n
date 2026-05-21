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

    // MARK: - Nested: AssetsOutputConfig

    public struct AssetsOutputConfig: Sendable, Codable, Equatable {
        /// Whether to generate `Assets.swift` during `swiftl10n scan`. Default: `false`.
        public let enabled: Bool
        /// Where to write `Assets.swift`, relative to the config file's directory.
        public let path: String
        /// Root enum name in the generated file. Default: `Assets`.
        public let enumName: String

        public init(
            enabled: Bool = false,
            path: String = "Sources/Generated/Assets.swift",
            enumName: String = "Assets"
        ) {
            self.enabled  = enabled
            self.path     = path
            self.enumName = enumName
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case path
            case enumName = "enum_name"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled  = try c.decodeIfPresent(Bool.self,   forKey: .enabled)  ?? false
            path     = try c.decodeIfPresent(String.self, forKey: .path)     ?? "Sources/Generated/Assets.swift"
            enumName = try c.decodeIfPresent(String.self, forKey: .enumName) ?? "Assets"
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

        public init(
            path: String = "Sources/Generated/i18n.swift",
            enumName: String = "i18n",
            tableName: String = "Localizable"
        ) {
            self.path = path
            self.enumName = enumName
            self.tableName = tableName
        }

        enum CodingKeys: String, CodingKey {
            case path
            case enumName = "enum_name"
            case tableName = "table_name"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path      = try c.decodeIfPresent(String.self, forKey: .path)      ?? "Sources/Generated/i18n.swift"
            enumName  = try c.decodeIfPresent(String.self, forKey: .enumName)  ?? "i18n"
            tableName = try c.decodeIfPresent(String.self, forKey: .tableName) ?? "Localizable"
        }
    }

    // MARK: - Default

    public static let `default` = SwiftL10nConfig(
        sources: ["Sources"],
        output: .init(),
        minimumConfidence: 0.85,
        exclude: [],
        incremental: false,
        assets: .init()
    )

    // MARK: - Init

    public init(
        sources: [String] = ["Sources"],
        output: OutputConfig = .init(),
        minimumConfidence: Double = 0.85,
        exclude: [String] = [],
        incremental: Bool = false,
        assets: AssetsOutputConfig = .init()
    ) {
        self.sources = sources
        self.output = output
        self.minimumConfidence = minimumConfidence
        self.exclude = exclude
        self.incremental = incremental
        self.assets = assets
    }

    // MARK: - CodingKeys (snake_case YAML ↔ camelCase Swift)

    enum CodingKeys: String, CodingKey {
        case sources
        case output
        case minimumConfidence = "minimum_confidence"
        case exclude
        case incremental
        case assets
    }

    // Provide defaults for every field so a minimal YAML (e.g. `sources: [Sources]`) is valid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources           = try c.decodeIfPresent([String].self, forKey: .sources)                ?? ["Sources"]
        output            = try c.decodeIfPresent(OutputConfig.self, forKey: .output)             ?? .init()
        minimumConfidence = try c.decodeIfPresent(Double.self, forKey: .minimumConfidence)        ?? 0.85
        exclude           = try c.decodeIfPresent([String].self, forKey: .exclude)                ?? []
        incremental       = try c.decodeIfPresent(Bool.self, forKey: .incremental)                ?? false
        assets            = try c.decodeIfPresent(AssetsOutputConfig.self, forKey: .assets)       ?? .init()
    }
}
