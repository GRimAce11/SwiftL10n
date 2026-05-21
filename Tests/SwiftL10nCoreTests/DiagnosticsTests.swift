import XCTest
@testable import SwiftL10nCore

final class DiagnosticsTests: XCTestCase {

    // MARK: - DiagnosticsEngine

    func testEmitAndRetrieve() {
        let engine = DiagnosticsEngine()
        engine.emit(.warning, "unused string", at: SourceLocation(file: "Foo.swift", line: 3, column: 9))
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].severity, .warning)
        XCTAssertFalse(engine.hasErrors)
    }

    func testHasErrorsFlag() {
        let engine = DiagnosticsEngine()
        engine.emit(.warning, "w1")
        engine.emit(.error,   "e1")
        XCTAssertTrue(engine.hasErrors)
        XCTAssertEqual(engine.errorCount,   1)
        XCTAssertEqual(engine.warningCount, 1)
    }

    func testEmitOrder() {
        let engine = DiagnosticsEngine()
        engine.emit(.note,    "first")
        engine.emit(.warning, "second")
        engine.emit(.error,   "third")
        let messages = engine.diagnostics.map(\.message)
        XCTAssertEqual(messages, ["first", "second", "third"])
    }

    func testEmptyEngineHasNoErrors() {
        let engine = DiagnosticsEngine()
        XCTAssertFalse(engine.hasErrors)
        XCTAssertTrue(engine.diagnostics.isEmpty)
    }

    // MARK: - Diagnostic Description

    func testDescriptionWithLocation() {
        let loc = SourceLocation(file: "Bar.swift", line: 42, column: 5)
        let d = Diagnostic(severity: .warning, message: "hardcoded string", location: loc)
        XCTAssertEqual(d.description, "Bar.swift:42:5: warning: hardcoded string")
    }

    func testDescriptionWithoutLocation() {
        let d = Diagnostic(severity: .error, message: "file not found")
        XCTAssertEqual(d.description, "error: file not found")
    }

    func testNoteDescription() {
        let d = Diagnostic(severity: .note, message: "consider localizing")
        XCTAssertEqual(d.description, "note: consider localizing")
    }

    // MARK: - Severity Ordering

    func testSeverityOrdering() {
        XCTAssertLessThan(Diagnostic.Severity.note,    .warning)
        XCTAssertLessThan(Diagnostic.Severity.warning, .error)
        XCTAssertGreaterThan(Diagnostic.Severity.error, .note)
    }
}
