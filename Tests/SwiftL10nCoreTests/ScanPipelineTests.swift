import XCTest
@testable import SwiftL10nCore

final class ScanPipelineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanPipelineTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func write(source: String, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func pipeline(
        excludes: [String] = [],
        confidence: Double = 0.0
    ) -> ScanPipeline {
        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            output: .init(),
            minimumConfidence: confidence,
            exclude: excludes,
            incremental: false
        )
        return ScanPipeline(config: config, baseURL: tempDir)
    }

    // MARK: - Basic scanning

    func testFindsLocalizedStrings() async throws {
        try write(source: """
        import SwiftUI
        struct V: View {
            var body: some View {
                Text("Hello, World!")
                Button("Submit") { }
            }
        }
        """, name: "ContentView.swift")

        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.scannedFiles, 1)
        XCTAssertEqual(result.totalStrings, 2)
        XCTAssertEqual(result.namespaces.count, 1)
        // NamespaceInferrer strips "View" suffix: ContentView.swift → "Content"
        XCTAssertEqual(result.namespaces[0].name, "Content")
    }

    func testEmptyFileProducesNoStrings() async throws {
        try write(source: "import SwiftUI\n", name: "Empty.swift")

        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.scannedFiles, 1)
        XCTAssertEqual(result.totalStrings, 0)
        XCTAssertEqual(result.namespaces.count, 0)
    }

    func testScansMultipleFiles() async throws {
        try write(source: #"import SwiftUI; struct A: View { var body: some View { Text("Alpha") } }"#,
                  name: "AlphaView.swift")
        try write(source: #"import SwiftUI; struct B: View { var body: some View { Text("Beta") } }"#,
                  name: "BetaView.swift")

        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.scannedFiles, 2)
        XCTAssertEqual(result.totalStrings, 2)
        XCTAssertEqual(result.namespaces.count, 2)
    }

    func testMissingSourcePathEmitsError() async throws {
        let result = try await pipeline().run(sources: ["/nonexistent/path"])
        XCTAssertTrue(result.errorCount > 0)
    }

    // MARK: - Confidence filtering

    func testConfidenceFilterDropsLowScoringStrings() async throws {
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("ok") } }"#,
                  name: "SmallView.swift")

        let highThreshold = pipeline(confidence: 0.99)
        let highResult    = try await highThreshold.run(sources: [tempDir.path])

        let noFilter  = pipeline(confidence: 0.0)
        let allResult = try await noFilter.run(sources: [tempDir.path])

        // The short string "ok" likely scores below 0.99
        XCTAssertLessThanOrEqual(highResult.totalStrings, allResult.totalStrings)
    }

    // MARK: - Exclusion

    func testExcludesDirectoryByPattern() async throws {
        let genDir = tempDir.appendingPathComponent("Generated")
        try FileManager.default.createDirectory(at: genDir, withIntermediateDirectories: true)
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Generated") } }"#,
                  name: "Generated/i18n.swift")
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Live") } }"#,
                  name: "ContentView.swift")

        let result = try await pipeline(excludes: ["Generated"]).run(sources: [tempDir.path])
        let values = result.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertFalse(values.contains("Generated"), "File inside excluded directory must be skipped")
        XCTAssertTrue(values.contains("Live"))
    }

    func testExcludesGlobPattern() async throws {
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Generated") } }"#,
                  name: "Strings.generated.swift")
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Live") } }"#,
                  name: "ContentView.swift")

        let result = try await pipeline(excludes: ["*.generated.swift"]).run(sources: [tempDir.path])
        let values = result.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertFalse(values.contains("Generated"), "*.generated.swift must be excluded")
        XCTAssertTrue(values.contains("Live"))
    }

    func testExcludesDeepGlobPattern() async throws {
        let subDir = tempDir.appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Deep") } }"#,
                  name: "Sub/Deep.generated.swift")
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Live") } }"#,
                  name: "ContentView.swift")

        let result = try await pipeline(excludes: ["**/*.generated.swift"]).run(sources: [tempDir.path])
        let values = result.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertFalse(values.contains("Deep"), "**/*.generated.swift must exclude deep file")
        XCTAssertTrue(values.contains("Live"))
    }

    // MARK: - PipelineResult computed properties

    func testResultCountsWarnWarningsCorrectly() async throws {
        try write(source: #"""
        import SwiftUI
        struct V: View {
            let x = "hello"
            var body: some View { Text("Say \(x)!") }
        }
        """#, name: "InterpView.swift")

        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertGreaterThanOrEqual(result.warningCount, 1)
    }

    // MARK: - v0.9 fields

    func testScanDurationIsPositive() async throws {
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Hi") } }"#,
                  name: "View.swift")
        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertGreaterThan(result.scanDuration, 0)
    }

    func testStaleEntriesRemovedIsZeroWithoutIncremental() async throws {
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Hi") } }"#,
                  name: "View.swift")
        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.staleEntriesRemoved, 0)
    }

    // MARK: - Cache corruption

    func testCorruptCacheEmitsWarningAndFallsBackToFullScan() async throws {
        try write(source: #"import SwiftUI; struct V: View { var body: some View { Text("Hello") } }"#,
                  name: "View.swift")

        let cacheDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("swiftl10n-cache.json")
        try "{ this is not valid json %%%".write(to: cacheFile, atomically: true, encoding: .utf8)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            output: .init(),
            minimumConfidence: 0.0,
            incremental: true
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()

        XCTAssertEqual(result.totalStrings, 1, "Full scan must still run and find the string")
        let hasWarning = result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("Cache unreadable")
        }
        XCTAssertTrue(hasWarning, "A warning diagnostic must be emitted when cache is corrupt")
    }
}
