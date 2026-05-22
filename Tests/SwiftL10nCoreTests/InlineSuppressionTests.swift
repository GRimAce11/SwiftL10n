import XCTest
@testable import SwiftL10nCore

final class InlineSuppressionTests: XCTestCase {

    // MARK: - InlineSuppression construction

    func testEmptySourceProducesEmptyIndex() {
        let s = InlineSuppression(source: "import SwiftUI\nstruct V: View {}")
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.count, 0)
    }

    func testSingleIgnoreComment() {
        let source = """
        import SwiftUI
        let x = Text("ignore me") // swiftl10n:ignore
        let y = Text("keep me")
        """
        let s = InlineSuppression(source: source)
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s.isSuppressed(line: 2))
        XCTAssertFalse(s.isSuppressed(line: 3))
    }

    func testMultipleIgnoreComments() {
        let source = """
        import SwiftUI
        Text("a") // swiftl10n:ignore
        Text("b")
        Text("c") // swiftl10n:ignore
        Text("d")
        """
        let s = InlineSuppression(source: source)
        XCTAssertEqual(s.count, 2)
        XCTAssertTrue(s.isSuppressed(line: 2))
        XCTAssertFalse(s.isSuppressed(line: 3))
        XCTAssertTrue(s.isSuppressed(line: 4))
        XCTAssertFalse(s.isSuppressed(line: 5))
    }

    func testIgnoreWithTrailingComment() {
        // swiftl10n:ignore may have additional text after it
        let source = #"Text("foo") // swiftl10n:ignore — not a real UI string"#
        let s = InlineSuppression(source: source)
        XCTAssertTrue(s.isSuppressed(line: 1))
    }

    func testStaticEmpty() {
        XCTAssertTrue(InlineSuppression.empty.isEmpty)
        XCTAssertFalse(InlineSuppression.empty.isSuppressed(line: 1))
    }

    // MARK: - Integration with StringScanner

    func testScannerSkipsIgnoredLines() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Text("Visible string")
                Text("Suppressed") // swiftl10n:ignore
                Button("Also visible") {}
            }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")

        let values = result.detectedStrings.map(\.value)
        XCTAssertTrue(values.contains("Visible string"),  "Visible string must be detected")
        XCTAssertTrue(values.contains("Also visible"),    "Also visible must be detected")
        XCTAssertFalse(values.contains("Suppressed"),    "Suppressed line must be skipped")
    }

    func testScannerEmitsNoteForIgnoredLine() {
        let source = #"""
        import SwiftUI
        struct V: View {
            var body: some View { Text("internal_key") } // swiftl10n:ignore
        }
        """#
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")

        XCTAssertTrue(result.detectedStrings.isEmpty, "Ignored line must produce no detections")
        let notes = result.diagnostics.filter { $0.severity == .note && $0.message.contains("swiftl10n:ignore") }
        XCTAssertGreaterThanOrEqual(notes.count, 1, "A .note diagnostic should be emitted for the suppressed line")
    }

    func testScannerDetectsOtherStringsOnNonIgnoredLines() {
        let source = """
        import SwiftUI
        struct V: View {
            var body: some View {
                Text("Not ignored")
                Text("Also not ignored")
            }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "V.swift")
        XCTAssertEqual(result.detectedStrings.count, 2)
    }

    func testUIKitAssignmentIgnoredLine() {
        let source = """
        import UIKit
        class VC: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Debug Title" // swiftl10n:ignore
                navigationItem.title = "Real Title"
            }
        }
        """
        let scanner = StringScanner(minimumConfidence: 0.0)
        let result  = scanner.scan(source: source, filePath: "VC.swift")

        let values = result.detectedStrings.map(\.value)
        XCTAssertFalse(values.contains("Debug Title"), "Ignored assignment must be skipped")
        XCTAssertTrue(values.contains("Real Title"), "Non-ignored assignment must be detected")
    }
}
