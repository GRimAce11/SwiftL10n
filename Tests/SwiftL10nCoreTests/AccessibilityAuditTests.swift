import XCTest
@testable import SwiftL10nCore

final class AccessibilityAuditTests: XCTestCase {

    private let auditor = AccessibilityAuditor()

    private func audit(_ source: String) -> [Diagnostic] {
        auditor.audit(source: source, filePath: "TestView.swift")
    }

    // MARK: - Flagged cases

    func testImageLiteralWithoutModifierIsFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Image("profile_icon") }
        }
        """
        let diags = audit(source)
        XCTAssertEqual(diags.count, 1)
        XCTAssertEqual(diags[0].severity, .warning)
        XCTAssertTrue(diags[0].message.contains("accessibility modifier"))
    }

    func testMultipleImageLiteralsAllFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("logo")
                Image("banner")
            }
        }
        """
        let diags = audit(source)
        XCTAssertEqual(diags.count, 2)
    }

    func testFlaggedDiagnosticHasLocation() {
        let source = "import SwiftUI\nstruct V: View { var body: some View { Image(\"icon\") } }"
        let diags = audit(source)
        XCTAssertFalse(diags.isEmpty)
        XCTAssertNotNil(diags[0].location)
        XCTAssertEqual(diags[0].location?.file, "TestView.swift")
    }

    // MARK: - Not flagged: accessibility modifiers present

    func testImageWithAccessibilityLabelNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("profile_icon").accessibilityLabel("User profile picture")
            }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    func testImageWithAccessibilityHiddenNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("decorative_bg").accessibilityHidden(true)
            }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    func testImageWithAccessibilityElementNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("icon").accessibilityElement(children: .combine)
            }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    func testModifierChainIncludingAccessibilityNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Image("logo")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Company logo")
            }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    // MARK: - Not flagged: excluded call forms

    func testSystemNameImageNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Image(systemName: "star.fill") }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    func testDecorativeImageNotFlagged() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View { Image(decorative: "background_texture") }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    func testNonStringArgumentNotFlagged() {
        // Image(uiImage:) — no string literal
        let source = """
        import SwiftUI
        struct V: View {
            let img: UIImage
            var body: some View { Image(uiImage: img) }
        }
        """
        XCTAssertTrue(audit(source).isEmpty)
    }

    // MARK: - Pipeline integration

    func testAccessibilityAuditDisabledByDefaultInPipeline() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        import SwiftUI
        struct V: View { var body: some View { Image("logo") } }
        """.write(to: tempDir.appendingPathComponent("V.swift"), atomically: true, encoding: .utf8)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            accessibilityAudit: .init(enabled: false)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.accessibilityWarnings, 0, "Audit must be opt-in — off by default")
    }

    func testAccessibilityAuditEnabledReportsWarnings() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessTestOn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        import SwiftUI
        struct V: View { var body: some View { Image("logo").accessibilityHidden(true) } }
        """.write(to: tempDir.appendingPathComponent("Labeled.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI
        struct V2: View { var body: some View { Image("banner") } }
        """.write(to: tempDir.appendingPathComponent("Unlabeled.swift"), atomically: true, encoding: .utf8)

        let config = SwiftL10nConfig(
            sources: [tempDir.path],
            accessibilityAudit: .init(enabled: true)
        )
        let result = try await ScanPipeline(config: config, baseURL: tempDir).run()
        XCTAssertEqual(result.accessibilityWarnings, 1, "Only the unlabeled Image should be flagged")
    }
}
