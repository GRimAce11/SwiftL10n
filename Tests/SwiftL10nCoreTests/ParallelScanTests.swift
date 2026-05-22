import XCTest
@testable import SwiftL10nCore

/// Verifies that parallel scanning produces the same results as sequential scanning
/// and that the new v0.9 `PipelineResult` fields are correctly populated.
final class ParallelScanTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParallelScanTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func write(_ source: String, name: String) throws {
        try source.write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func pipeline(incremental: Bool = false) -> ScanPipeline {
        ScanPipeline(
            config: SwiftL10nConfig(sources: [tempDir.path], incremental: incremental),
            baseURL: tempDir
        )
    }

    // MARK: - Correctness

    func testParallelScanFindsAllStrings() async throws {
        for i in 1...5 {
            try write(
                "import SwiftUI; struct V\(i): View { var body: some View { Text(\"String \(i)\") } }",
                name: "View\(i).swift"
            )
        }
        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.scannedFiles, 5)
        XCTAssertEqual(result.totalStrings, 5)
    }

    func testParallelScanDeterministicOrder() async throws {
        for i in 1...4 {
            try write(
                "import SwiftUI; struct V\(i): View { var body: some View { Text(\"Val\(i)\") } }",
                name: "\(i)View.swift"
            )
        }
        let r1 = try await pipeline().run(sources: [tempDir.path])
        let r2 = try await pipeline().run(sources: [tempDir.path])

        XCTAssertEqual(r1.namespaces.map(\.name), r2.namespaces.map(\.name),
            "Namespace order must be deterministic across parallel runs")
        XCTAssertEqual(r1.totalStrings, r2.totalStrings)
    }

    func testParallelScanEmptyDirectoryProducesZeroStrings() async throws {
        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertEqual(result.scannedFiles, 0)
        XCTAssertEqual(result.totalStrings, 0)
    }

    // MARK: - PipelineResult v0.9 fields

    func testScanDurationIsPositive() async throws {
        try write(
            "import SwiftUI; struct V: View { var body: some View { Text(\"Hello\") } }",
            name: "V.swift"
        )
        let result = try await pipeline().run(sources: [tempDir.path])
        XCTAssertGreaterThan(result.scanDuration, 0, "scanDuration must be positive")
    }

    func testStaleEntriesRemovedIsZeroWithoutIncrementalCache() async throws {
        try write("import SwiftUI\n", name: "Empty.swift")
        let result = try await pipeline(incremental: false).run(sources: [tempDir.path])
        XCTAssertEqual(result.staleEntriesRemoved, 0)
    }

    func testStaleEntriesRemovedAfterFileDeletion() async throws {
        let fileURL = tempDir.appendingPathComponent("ToDelete.swift")
        try "import SwiftUI; struct V: View { var body: some View { Text(\"Gone\") } }".write(
            to: fileURL, atomically: true, encoding: .utf8
        )

        // First run — populates cache
        _ = try await pipeline(incremental: true).run(sources: [tempDir.path])

        // Delete the file
        try FileManager.default.removeItem(at: fileURL)

        // Second run — stale entry must be pruned
        let result = try await pipeline(incremental: true).run(sources: [tempDir.path])
        XCTAssertEqual(result.staleEntriesRemoved, 1,
            "Deleted file's cache entry must be removed on next run")
    }

    // MARK: - Inline suppression still works through parallel path

    func testInlineSuppressionRespectedInParallelScan() async throws {
        try write(
            "import SwiftUI; struct V: View { var body: some View { Text(\"Suppressed\") } } // swiftl10n:ignore",
            name: "SuppressedView.swift"
        )
        try write(
            "import SwiftUI; struct V2: View { var body: some View { Text(\"Visible\") } }",
            name: "VisibleView.swift"
        )
        let result = try await pipeline().run(sources: [tempDir.path])
        let values = result.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertFalse(values.contains("Suppressed"), "Suppressed string must not appear in parallel result")
        XCTAssertTrue(values.contains("Visible"))
    }
}
