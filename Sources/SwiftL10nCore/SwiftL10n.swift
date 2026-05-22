import Foundation

/// Primary entry point for SwiftL10n's in-project development workflow.
///
/// Call `SwiftL10n.scan(projectPath:)` from any SwiftUI view or UIKit entry point
/// during development. One call generates both `i18n.swift` and `Assets.swift`,
/// validates all asset references, and prints a full diagnostic report.
///
/// **SwiftUI:**
/// ```swift
/// .task {
///     _ = try? await SwiftL10n.scan(projectPath: "/path/to/Sources/YourApp")
/// }
/// ```
///
/// **UIKit:**
/// ```swift
/// Task { _ = try? await SwiftL10n.scan(projectPath: "/path/to/YourApp") }
/// ```
///
/// Both generated files are written to `projectPath/Generated/` by default.
/// Pass explicit output paths or disable asset generation for more control:
///
/// ```swift
/// try await SwiftL10n.scan(
///     projectPath:        "/path/to/Sources/YourApp",
///     stringsOutput:      "/path/to/Sources/YourApp/Generated/i18n.swift",
///     assetsOutput:       "/path/to/Sources/YourApp/Generated/Assets.swift",
///     minimumConfidence:  0.9,
///     generateAssets:     true
/// )
/// ```
public enum SwiftL10n {

    // MARK: - Result

    /// Combined result from a single `scan()` invocation.
    public struct ScanResult: Sendable {
        /// Localization scan summary — string count, namespace count, warning count,
        /// missing asset diagnostics, and the URL of the written `i18n.swift`.
        public let strings: StringsGenerator.Result
        /// Asset generation summary — catalog count, image count, color count,
        /// and the URL of the written `Assets.swift`. `nil` when `generateAssets` is `false`.
        public let assets: AssetsGenerator.Result?
    }

    // MARK: - scan()

    /// Scan `projectPath` for localizable strings and asset references, then write
    /// `i18n.swift` and `Assets.swift` to the `Generated/` subfolder.
    ///
    /// This is the only call most projects need. Run it once to generate both files,
    /// then drag them into your Xcode target.
    ///
    /// - Parameters:
    ///   - projectPath: The directory containing your Swift source files. This is also
    ///     used as the starting point for `.xcassets` catalog discovery (walks up to
    ///     three levels).
    ///   - stringsOutput: Where to write `i18n.swift`. Defaults to
    ///     `projectPath/Generated/i18n.swift`.
    ///   - assetsOutput: Where to write `Assets.swift`. Defaults to
    ///     `projectPath/Generated/Assets.swift`. Ignored when `generateAssets` is `false`.
    ///   - minimumConfidence: Strings scored below this threshold are ignored. Default `0.85`.
    ///   - generateAssets: When `true` (default), also generates `Assets.swift` from any
    ///     `.xcassets` catalogs found near `projectPath`.
    /// - Returns: A `ScanResult` with both generation summaries.
    @discardableResult
    public static func scan(
        projectPath: String,
        stringsOutput: String? = nil,
        assetsOutput: String? = nil,
        minimumConfidence: Double = 0.85,
        generateAssets: Bool = true
    ) async throws -> ScanResult {
        let resolvedStringsOutput = stringsOutput
            ?? "\(projectPath)/Generated/i18n.swift"
        let resolvedAssetsOutput = assetsOutput
            ?? "\(projectPath)/Generated/Assets.swift"

        // Localization scan + missing-asset validation
        let stringsResult = try await generateStrings(
            sourcesPath: projectPath,
            outputPath: resolvedStringsOutput,
            minimumConfidence: minimumConfidence
        )

        // Asset code generation
        var assetsResult: AssetsGenerator.Result? = nil
        if generateAssets {
            assetsResult = try await SwiftL10nCore.generateAssets(
                sourcesPath: projectPath,
                outputPath: resolvedAssetsOutput
            )
        }

        return ScanResult(strings: stringsResult, assets: assetsResult)
    }
}
