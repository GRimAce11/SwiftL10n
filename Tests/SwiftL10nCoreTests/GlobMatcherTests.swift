import XCTest
@testable import SwiftL10nCore

final class GlobMatcherTests: XCTestCase {

    // MARK: - Exact / literal

    func testLiteralMatchesExactPath() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "Sources/App/View.swift",
                                          path: "Sources/App/View.swift"))
    }

    func testLiteralDoesNotMatchPartialPath() {
        XCTAssertFalse(GlobMatcher.matches(pattern: "Sources/App",
                                           path: "Sources/App/View.swift"))
    }

    // MARK: - Single * (no slash crossing)

    func testStarMatchesFilename() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "*.swift", path: "View.swift"))
    }

    func testStarDoesNotCrossSlash() {
        XCTAssertFalse(GlobMatcher.matches(pattern: "*.swift", path: "Sources/View.swift"))
    }

    func testStarMatchesExtension() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "View.*", path: "View.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "View.*", path: "Layout.swift"))
    }

    func testStarInMiddle() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "Sources/*/View.swift",
                                          path: "Sources/App/View.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "Sources/*/View.swift",
                                           path: "Sources/App/Sub/View.swift"))
    }

    func testGeneratedSwiftExtension() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "*.generated.swift",
                                          path: "Strings.generated.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "*.generated.swift",
                                           path: "Sources/Strings.generated.swift"))
    }

    // MARK: - Double ** (crosses slashes)

    func testDoubleStarMatchesAnyDepth() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "**/*.generated.swift",
                                          path: "Sources/App/Strings.generated.swift"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "**/*.generated.swift",
                                          path: "Strings.generated.swift"))
    }

    func testDoubleStarPrefixMatchesAnyDirectory() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "**/Generated",
                                          path: "Sources/Generated"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "**/Generated",
                                          path: "Sources/App/Generated"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "**/Generated",
                                           path: "Sources/NotGenerated"))
    }

    func testDoubleStarMidPattern() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "Sources/**/View.swift",
                                          path: "Sources/App/View.swift"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "Sources/**/View.swift",
                                          path: "Sources/App/Sub/View.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "Sources/**/View.swift",
                                           path: "Other/App/View.swift"))
    }

    func testBareDoubleStarMatchesAnything() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "**", path: "anything/goes/here.swift"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "**", path: ""))
    }

    // MARK: - ? wildcard

    func testQuestionMarkMatchesSingleChar() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "View?.swift", path: "Views.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "View?.swift", path: "ViewAB.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "View?.swift", path: "View.swift"))
    }

    func testQuestionMarkDoesNotMatchSlash() {
        XCTAssertFalse(GlobMatcher.matches(pattern: "?ources/App.swift", path: "/ources/App.swift"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "?ources/App.swift", path: "Sources/App.swift"))
    }

    // MARK: - Edge cases

    func testEmptyPatternMatchesOnlyEmptyPath() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "", path: ""))
        XCTAssertFalse(GlobMatcher.matches(pattern: "", path: "something"))
    }

    func testEmptyPathMatchesOnlyEmptyPattern() {
        XCTAssertFalse(GlobMatcher.matches(pattern: "*.swift", path: ""))
    }

    func testDeepPathWithStarStar() {
        XCTAssertTrue(GlobMatcher.matches(
            pattern: "**/Generated/**/*.swift",
            path: "Sources/App/Generated/i18n/i18n.swift"
        ))
    }
}

// MARK: - ScanPipeline.excludes() integration

final class ExclusionMatchingTests: XCTestCase {

    func testPlainDirectoryExcludesContents() {
        XCTAssertTrue(ScanPipeline.excludes(relativePath: "Sources/Generated/i18n.swift",
                                            pattern: "Sources/Generated"))
        XCTAssertFalse(ScanPipeline.excludes(relativePath: "Sources/App/View.swift",
                                              pattern: "Sources/Generated"))
    }

    func testPlainDirectoryWithTrailingSlash() {
        XCTAssertTrue(ScanPipeline.excludes(relativePath: "Sources/Generated/i18n.swift",
                                            pattern: "Sources/Generated/"))
    }

    func testGlobExcludesGeneratedExtension() {
        XCTAssertTrue(ScanPipeline.excludes(relativePath: "Sources/App/Foo.generated.swift",
                                            pattern: "**/*.generated.swift"))
        XCTAssertFalse(ScanPipeline.excludes(relativePath: "Sources/App/Foo.swift",
                                              pattern: "**/*.generated.swift"))
    }

    func testExactFileExclusion() {
        XCTAssertTrue(ScanPipeline.excludes(relativePath: "Sources/Generated/i18n.swift",
                                            pattern: "Sources/Generated/i18n.swift"))
        XCTAssertFalse(ScanPipeline.excludes(relativePath: "Sources/App/View.swift",
                                              pattern: "Sources/Generated/i18n.swift"))
    }
}
