import AppKit
import XCTest
import SASCore
@testable import LocalStat

final class EditorIntegrationTests: XCTestCase {
    @MainActor func testAppOpenSaveRunAndDiagnosticsInBothAppearances() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = root.appendingPathComponent("dist/LocalStat.app/Contents/Helpers/opensas")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Build the packaged runtime first") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStat UI \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "data d; x=42; run;".write(to: folder.appendingPathComponent("include file.sas"), atomically: true, encoding: .utf8)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let app = AppDelegate()
            app.projectURL = folder
            app.runner = LocalRuntimeRunner(executable: binary)
            app.buildMenu()
            app.buildWindow()
            app.window.appearance = NSAppearance(named: name)
            let file = folder.appendingPathComponent("saved \(name.rawValue).sas")
            try "data old; run;".write(to: file, atomically: true, encoding: .utf8)
            app.open(file)
            let document = try XCTUnwrap(app.current)
            document.textView.selectAll(nil)
            document.textView.insertText("%include 'include file.sas'; proc print data=d; run;", replacementRange: document.textView.selectedRange())
            XCTAssertTrue(document.isDirty)
            app.runProgram()
            for _ in 0..<500 {
                if app.lastResult != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(app.lastResult?.status, .success)
            XCTAssertTrue(app.outputView.string.contains("42"))
            let tableView = try XCTUnwrap(app.tableScroll.documentView as? TableDocumentView)
            XCTAssertEqual(tableView.tables.count, 1)
            XCTAssertTrue((tableView.accessibilityValue() as? String)?.contains("42") ?? false)
            XCTAssertTrue(app.save(document))
            XCTAssertFalse(document.isDirty)
            XCTAssertEqual(try String(contentsOf: file), document.textView.string)
            document.textView.string = "proc not_implemented; run;"
            app.runProgram()
            for _ in 0..<500 {
                if app.lastResult != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertNotEqual(app.lastResult?.status, .success)
            XCTAssertFalse(app.diagnostics.isEmpty)
            XCTAssertTrue(app.runButton.isEnabled)
            document.textView.string = "data _null_; do i=1 to 5000; put i; end; run;"
            app.runProgram()
            for _ in 0..<500 {
                if app.lastResult != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(app.lastResult?.status, .success)
            XCTAssertTrue(app.outputView.string.contains("5000"))
            let report = RunReport(result: try XCTUnwrap(app.lastResult), appVersion: "test", runtimeVersion: "bundled")
            try PDFReportRenderer.write(report, to: folder.appendingPathComponent("\(name.rawValue).pdf"))
            document.textView.string = "data _null_; do i=1 to 10000000000; x=sqrt(i); end; run;"
            app.runProgram()
            for _ in 0..<100 {
                if app.runner.isRunning { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            app.stopProgram()
            for _ in 0..<500 {
                if app.lastResult != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(app.lastResult?.status, .cancelled)
            XCTAssertTrue(app.runButton.isEnabled)
            app.window.delegate = nil
            app.window.close()
        }
    }
    @MainActor func testPastedSourceIsUnchangedInBothAppearances() throws {
        _ = NSApplication.shared
        let source = "title 'Unicode café 😀 (literal)';\ndata d;\n  x=(1+2);\nrun;"
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let document = EditorDocument(url: nil, source: "")
            document.textView.appearance = try XCTUnwrap(NSAppearance(named: name))
            document.textView.insertText(source, replacementRange: NSRange(location: 0, length: 0))
            document.highlight()
            XCTAssertEqual(document.textView.string, source)
            XCTAssertTrue(document.isDirty)
        }
    }

    @MainActor func testAutomaticPairAndUndoInBothAppearances() throws {
        _ = NSApplication.shared
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let document = EditorDocument(url: nil, source: "")
            let editor = document.textView
            editor.appearance = try XCTUnwrap(NSAppearance(named: name))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = document.scrollView
            window.makeFirstResponder(editor)
            editor.undoManager?.beginUndoGrouping()
            editor.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.undoManager?.endUndoGrouping()
            XCTAssertEqual(editor.string, "()")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
            let undo = try XCTUnwrap(editor.undoManager)
            XCTAssertTrue(undo.canUndo)
            undo.undo()
            XCTAssertEqual(editor.string, "")
            window.close()
        }
    }
}
