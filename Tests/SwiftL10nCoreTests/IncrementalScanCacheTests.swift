import XCTest
@testable import SwiftL10nCore

final class IncrementalScanCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanCacheTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - SHA-256 hashing

    func testHashIsConsistentForSameContent() throws {
        let url = tempDir.appendingPathComponent("a.swift")
        let content = "let x = 1"
        try content.write(to: url, atomically: true, encoding: .utf8)

        let h1 = try IncrementalScanCache.contentHash(of: url)
        let h2 = try IncrementalScanCache.contentHash(of: url)
        XCTAssertEqual(h1, h2)
    }

    func testHashChangesWhenContentChanges() throws {
        let url = tempDir.appendingPathComponent("b.swift")
        try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
        let h1 = try IncrementalScanCache.contentHash(of: url)

        try "let x = 2".write(to: url, atomically: true, encoding: .utf8)
        let h2 = try IncrementalScanCache.contentHash(of: url)

        XCTAssertNotEqual(h1, h2)
    }

    func testHashIsHex64Chars() throws {
        let url = tempDir.appendingPathComponent("c.swift")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let hash = try IncrementalScanCache.contentHash(of: url)

        XCTAssertEqual(hash.count, 64, "SHA-256 hex digest should be 64 characters")
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testSha256HexMatchesKnownVector() {
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let hash = IncrementalScanCache.sha256Hex(Data())
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - ScanCache validation

    func testIsValidReturnsTrueForMatchingEntry() {
        var cache = ScanCache()
        cache.entries["/path/to/file.swift"] = ScanCacheEntry(
            contentHash: "abc123",
            swiftl10nVersion: SwiftL10nCoreVersion.current,
            detectedStrings: [],
            diagnostics: []
        )
        XCTAssertTrue(cache.isValid(for: "/path/to/file.swift", hash: "abc123"))
    }

    func testIsValidReturnsFalseForHashMismatch() {
        var cache = ScanCache()
        cache.entries["/path/to/file.swift"] = ScanCacheEntry(
            contentHash: "old-hash",
            swiftl10nVersion: SwiftL10nCoreVersion.current,
            detectedStrings: [],
            diagnostics: []
        )
        XCTAssertFalse(cache.isValid(for: "/path/to/file.swift", hash: "new-hash"))
    }

    func testIsValidReturnsFalseForVersionMismatch() {
        var cache = ScanCache()
        cache.entries["/path/to/file.swift"] = ScanCacheEntry(
            contentHash: "abc123",
            swiftl10nVersion: "0.0.0",   // stale version
            detectedStrings: [],
            diagnostics: []
        )
        XCTAssertFalse(cache.isValid(for: "/path/to/file.swift", hash: "abc123"))
    }

    func testIsValidReturnsFalseForMissingKey() {
        let cache = ScanCache()
        XCTAssertFalse(cache.isValid(for: "/nonexistent.swift", hash: "abc"))
    }

    // MARK: - Round-trip encode/decode

    func testCacheRoundTrip() throws {
        let string = DetectedString(
            value: "Hello",
            location: SourceLocation(file: "View.swift", line: 10, column: 5),
            context: .textView,
            confidence: 0.95
        )
        let entry = ScanCacheEntry(
            contentHash: "deadbeef",
            swiftl10nVersion: SwiftL10nCoreVersion.current,
            detectedStrings: [string],
            diagnostics: []
        )
        var original = ScanCache()
        original.entries["/some/View.swift"] = entry

        let cacheURL = tempDir.appendingPathComponent("test-cache.json")
        try IncrementalScanCache.save(original, to: cacheURL)
        let loaded = try IncrementalScanCache.load(from: cacheURL)

        XCTAssertEqual(loaded.entries.count, 1)
        let roundTripped = loaded.entries["/some/View.swift"]
        XCTAssertNotNil(roundTripped)
        XCTAssertEqual(roundTripped?.contentHash, "deadbeef")
        XCTAssertEqual(roundTripped?.detectedStrings.count, 1)
        XCTAssertEqual(roundTripped?.detectedStrings.first?.value, "Hello")
        XCTAssertEqual(roundTripped?.detectedStrings.first?.context, .textView)
    }

    func testCacheRoundTripUnknownContext() throws {
        let string = DetectedString(
            value: "Sheet Title",
            location: SourceLocation(file: "V.swift", line: 1, column: 1),
            context: .unknownUIContext(callee: "sheet")
        )
        var cache = ScanCache()
        cache.entries["/V.swift"] = ScanCacheEntry(
            contentHash: "hash",
            swiftl10nVersion: SwiftL10nCoreVersion.current,
            detectedStrings: [string],
            diagnostics: []
        )

        let url = tempDir.appendingPathComponent("ctx-cache.json")
        try IncrementalScanCache.save(cache, to: url)
        let loaded = try IncrementalScanCache.load(from: url)

        let ctx = loaded.entries["/V.swift"]?.detectedStrings.first?.context
        XCTAssertEqual(ctx, .unknownUIContext(callee: "sheet"))
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let nested = tempDir.appendingPathComponent(".build/swiftl10n-cache.json")
        let cache = ScanCache()
        XCTAssertNoThrow(try IncrementalScanCache.save(cache, to: nested))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testLoadThrowsForMissingFile() {
        let missing = tempDir.appendingPathComponent("nope.json")
        XCTAssertThrowsError(try IncrementalScanCache.load(from: missing))
    }

    // MARK: - ScanPipeline incremental integration

    func testIncrementalPipelineServesCacheOnSecondRun() async throws {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Cached String") }
        }
        """
        let fileURL = tempDir.appendingPathComponent("CachedView.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            minimumConfidence: 0.0,
            incremental: true
        )
        let pipeline = ScanPipeline(config: config, baseURL: tempDir)

        // First run — cold cache
        let run1 = try await pipeline.run(sources: [tempDir.path])
        XCTAssertEqual(run1.cacheHits, 0)
        XCTAssertGreaterThanOrEqual(run1.totalStrings, 1)

        // Second run — warm cache, file unchanged
        let run2 = try await pipeline.run(sources: [tempDir.path])
        XCTAssertEqual(run2.cacheHits, 1)
        XCTAssertEqual(run2.totalStrings, run1.totalStrings)
    }

    func testIncrementalPipelineRescansModifiedFile() async throws {
        let fileURL = tempDir.appendingPathComponent("ModView.swift")
        try """
        import SwiftUI
        struct V: View { var body: some View { Text("Version One") } }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            minimumConfidence: 0.0,
            incremental: true
        )
        let pipeline = ScanPipeline(config: config, baseURL: tempDir)

        // First run
        let run1 = try await pipeline.run(sources: [tempDir.path])
        let values1 = run1.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertTrue(values1.contains("Version One"))

        // Modify file
        try """
        import SwiftUI
        struct V: View { var body: some View { Text("Version Two") } }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        // Second run — cache miss, fresh scan
        let run2 = try await pipeline.run(sources: [tempDir.path])
        XCTAssertEqual(run2.cacheHits, 0)
        let values2 = run2.namespaces.flatMap { $0.strings.map(\.value) }
        XCTAssertTrue(values2.contains("Version Two"))
        XCTAssertFalse(values2.contains("Version One"))
    }
}
