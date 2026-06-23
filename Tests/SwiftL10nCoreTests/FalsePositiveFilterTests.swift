import XCTest
@testable import SwiftL10nCore

final class FalsePositiveFilterTests: XCTestCase {

    private let filter = FalsePositiveFilter()

    // MARK: - URL

    func testHTTPSURLExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "https://api.example.com"), .urlPattern)
    }

    func testHTTPURLExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "http://example.com/path"), .urlPattern)
    }

    func testFTPURLExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "ftp://files.example.com"), .urlPattern)
    }

    func testWWWPrefixExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "www.example.com"), .urlPattern)
    }

    // MARK: - File paths

    func testAbsoluteFilePathExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "/Users/dev/project/main.swift"), .filePathPattern)
    }

    func testHomeDirPathExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "~/Library/Preferences"), .filePathPattern)
    }

    // MARK: - Dot-separated identifiers

    func testSFSymbolExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "arrow.right"), .dotSeparatedIdentifier)
    }

    func testSFSymbolMultiComponentExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "person.crop.circle.badge.checkmark"), .dotSeparatedIdentifier)
    }

    func testLocalisationKeyExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "common.button.ok"), .dotSeparatedIdentifier)
    }

    func testSingleWordWithDotIsNotDotSeparated() {
        // "arrow" alone — no dots → not a dot-separated identifier
        XCTAssertNil(filter.exclusionReason(for: "arrow"))
    }

    // MARK: - Reverse DNS / analytics

    func testReverseDNSExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "com.example.app.event"), .analyticsKey)
    }

    func testOrgPrefixExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "org.swift.package"), .analyticsKey)
    }

    func testIOPrefixExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "io.github.tool"), .analyticsKey)
    }

    // MARK: - Snake case

    func testSnakeCaseExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "user_name"), .snakeCaseIdentifier)
    }

    func testSnakeCaseWithPrefixUnderscoreExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "profile_image_url"), .snakeCaseIdentifier)
    }

    func testScreamingSnakeCaseExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "SOME_FEATURE_FLAG"), .allCapsConstant)
    }

    // MARK: - camelCase

    func testCamelCaseExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "viewModel"), .camelCaseIdentifier)
    }

    func testLongCamelCaseExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "userDefaultsStorageKey"), .camelCaseIdentifier)
    }

    func testCamelCaseWithDigitsExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "featureFlag2"), .camelCaseIdentifier)
    }

    // MARK: - Empty string

    func testEmptyStringExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: ""), .emptyString)
    }

    func testWhitespaceOnlyExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "   "), .emptyString)
    }

    // MARK: - Valid UI strings that MUST pass through

    func testSimpleTitlePassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Settings"))
    }

    func testMultiWordPhrasePassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Delete Account"))
    }

    func testSentencePassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Are you sure you want to continue?"))
    }

    func testShortAbbreviationPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "OK"))
    }

    func testSingleWordPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Continue"))
    }

    func testPlaceholderTextPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Search…"))
    }

    func testStringWithHyphenPassesThrough() {
        // "e-mail" has a hyphen, not an underscore — should NOT be flagged as snake_case
        XCTAssertNil(filter.exclusionReason(for: "e-mail"))
    }

    // MARK: - Known product names (lowercase-starting) pass through

    func testIPhonePassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "iPhone"))
    }

    func testMacOSPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "macOS"))
    }

    func testIOSPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "iOS"))
    }

    // MARK: - Strings with spaces always bypass single-word patterns

    func testSnakeCaseLikeWithSpacePassesThrough() {
        // "user name" has a space — the snake_case check requires no spaces
        XCTAssertNil(filter.exclusionReason(for: "user name"))
    }

    // MARK: - Emoji-only strings

    func testSingleEmojiExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "👋"), .emojiOnly)
    }

    func testMultipleEmojisExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "👋🎉🔥"), .emojiOnly)
    }

    func testZWJSequenceExcluded() {
        // Family emoji built from ZWJ sequences: 👨‍👩‍👧
        XCTAssertEqual(filter.exclusionReason(for: "👨‍👩‍👧"), .emojiOnly)
    }

    func testSkinToneModifierExcluded() {
        // Thumbs up with medium skin tone modifier
        XCTAssertEqual(filter.exclusionReason(for: "👍🏽"), .emojiOnly)
    }

    func testFlagEmojiExcluded() {
        // Country flag (two regional indicator letters)
        XCTAssertEqual(filter.exclusionReason(for: "🇺🇸"), .emojiOnly)
    }

    func testEmojiWithSurroundingWhitespaceExcluded() {
        XCTAssertEqual(filter.exclusionReason(for: "  🎉  "), .emojiOnly)
    }

    func testTextWithTrailingEmojiPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Let's go 🚀"))
    }

    func testTextWithLeadingEmojiPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "👋 Hello"))
    }

    func testTextWithEmojiInMiddlePassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Save ✅ done"))
    }

    func testPlainTextWithNoEmojiPassesThrough() {
        XCTAssertNil(filter.exclusionReason(for: "Notifications"))
    }
}
