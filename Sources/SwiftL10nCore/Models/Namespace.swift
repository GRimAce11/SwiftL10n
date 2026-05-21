/// A logical grouping of detected strings, inferred from the source file they came from.
///
/// `SettingsView.swift` → namespace name `"Settings"` → generated as `extension i18n { enum Settings { … } }`.
///
/// One source file produces exactly one namespace.  Future phases may support
/// explicit annotation overrides (e.g. `// swiftl10n:namespace Onboarding`).
public struct Namespace: Sendable, Hashable {
    /// Swift identifier used as the enum name, e.g. `"Settings"`.
    public let name: String

    /// Absolute path of the source file this namespace was inferred from.
    public let sourceFile: String

    /// All localizable strings belonging to this namespace, in detection order.
    public let strings: [DetectedString]

    public init(name: String, sourceFile: String, strings: [DetectedString]) {
        self.name = name
        self.sourceFile = sourceFile
        self.strings = strings
    }
}
