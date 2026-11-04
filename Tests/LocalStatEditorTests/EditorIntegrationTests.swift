import AppKit
import XCTest
import SASCore
@testable import LocalStat

final class EditorIntegrationTests: XCTestCase {
    @MainActor func testCodeFirstLayoutRestoresSizesAndControls() throws {
        _ = NSApplication.shared
        let suiteName = "LocalStatLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let app = AppDelegate()
        app.layoutDefaults = defaults
        app.buildMenu()
        app.buildWindow()
        var reopened: AppDelegate?
        defer {
            reopened?.window.delegate = nil
            reopened?.window.close()
            app.window.delegate = nil
            app.window.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(app.navigatorPane.frame.width, 215, accuracy: 2)
        let initialFraction = app.resultsContainer.frame.height / app.editorResultsSplit.bounds.height
        XCTAssertEqual(initialFraction, 0.30, accuracy: 0.03)
        XCTAssertEqual(app.results.tabViewType, .noTabsNoBorder)
        let viewMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
        XCTAssertEqual(viewMenu.item(withTitle: "Hide Project Navigator")?.keyEquivalent, "0")
        XCTAssertEqual(viewMenu.item(withTitle: "Expand Results")?.keyEquivalent, "2")

        let project = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStatLayout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        app.projectURL = project
        app.refreshProject()
        XCTAssertFalse(app.projectHint.isHidden)
        try "data demo; run;".write(to: project.appendingPathComponent("demo.sas"), atomically: true, encoding: .utf8)
        app.refreshProject()
        XCTAssertTrue(app.projectHint.isHidden)

        app.navigatorSplit.setPosition(245, ofDividerAt: 0)
        app.editorResultsSplit.setPosition(390, ofDividerAt: 0)
        let savedWidth = app.navigatorPane.frame.width
        let savedResultsHeight = app.resultsContainer.frame.height
        XCTAssertEqual(defaults.double(forKey: "navigatorWidth"), Double(savedWidth), accuracy: 2)
        XCTAssertGreaterThan(defaults.double(forKey: "resultsFraction"), 0)

        app.toggleResultsExpansion()
        XCTAssertTrue(app.resultsExpanded)
        XCTAssertEqual(app.resultsContainer.frame.height / app.editorResultsSplit.bounds.height, 0.60, accuracy: 0.03)
        app.toggleResultsExpansion()
        XCTAssertEqual(app.resultsContainer.frame.height, savedResultsHeight, accuracy: 2)

        app.toggleNavigator()
        XCTAssertFalse(app.navigatorVisible)
        XCTAssertTrue(app.navigatorPane.isHidden)
        XCTAssertFalse(defaults.bool(forKey: "navigatorVisible"))

        let reopenedApp = AppDelegate()
        reopened = reopenedApp
        reopenedApp.layoutDefaults = defaults
        reopenedApp.buildWindow()
        XCTAssertFalse(reopenedApp.navigatorVisible)
        XCTAssertTrue(reopenedApp.navigatorPane.isHidden)
        reopenedApp.toggleNavigator()
        XCTAssertEqual(reopenedApp.navigatorPane.frame.width, savedWidth, accuracy: 2)
        XCTAssertEqual(reopenedApp.resultsContainer.frame.height / reopenedApp.editorResultsSplit.bounds.height,
                       savedResultsHeight / app.editorResultsSplit.bounds.height, accuracy: 0.03)

        reopenedApp.window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 540), display: true)
        reopenedApp.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(reopenedApp.tabs.frame.height, 160)
        XCTAssertGreaterThanOrEqual(reopenedApp.resultsContainer.frame.height, 140)
        XCTAssertLessThanOrEqual(reopenedApp.resultsSelector.frame.maxX, reopenedApp.resultsContainer.bounds.maxX)
        XCTAssertLessThanOrEqual(reopenedApp.expandResultsButton.frame.maxX, reopenedApp.resultsContainer.bounds.maxX)

        reopenedApp.resultsSelector.selectedSegment = 2
        reopenedApp.changeResultsView()
        XCTAssertEqual(reopenedApp.results.selectedTabViewItem?.identifier as? String, "diagnostics")
    }

    @MainActor func testAppearanceSelectorPersistsLightAndDark() throws {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        let suiteName = "LocalStatAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let app = AppDelegate()
        app.appearanceDefaults = defaults
        app.restoreAppearance()
        app.buildWindow()
        let editor = EditorDocument(url: nil, source: "data demo; x=1; run;")
        app.addDocument(editor)
        let table = ResultTable(procedure: "PRINT", title: "Demo",
                                headers: [ResultRow(kind: "header", cells: [ResultCell("x")])],
                                rows: [ResultRow(cells: [ResultCell("1")])])
        let tableView = TableDocumentView(tables: [table])
        app.tableScroll.documentView = tableView
        app.results.selectTabViewItem(at: 1)
        var reopened: AppDelegate?
        defer {
            reopened?.window.delegate = nil
            reopened?.window.close()
            app.window.delegate = nil
            app.window.close()
            NSApp.appearance = originalAppearance
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(app.appearancePreference, .system)
        XCTAssertNil(NSApp.appearance)
        XCTAssertEqual(app.appearancePopup.selectedItem?.title, "System")

        app.appearancePopup.selectItem(withTitle: "Dark")
        app.changeAppearance()
        XCTAssertEqual(app.appearancePreference, .dark)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertEqual(defaults.string(forKey: "appearancePreference"), "dark")
        XCTAssertEqual(editor.textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertEqual(tableView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertEqual(app.resultsSelector.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)

        let reopenedApp = AppDelegate()
        reopened = reopenedApp
        reopenedApp.appearanceDefaults = defaults
        reopenedApp.restoreAppearance()
        reopenedApp.buildWindow()
        XCTAssertEqual(reopenedApp.appearancePreference, .dark)
        XCTAssertEqual(reopenedApp.appearancePopup.selectedItem?.title, "Dark")

        app.results.selectTabViewItem(at: 0)
        app.appearancePopup.selectItem(withTitle: "Light")
        app.changeAppearance()
        app.results.selectTabViewItem(at: 1)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        XCTAssertEqual(defaults.string(forKey: "appearancePreference"), "light")
        XCTAssertEqual(editor.textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(tableView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(app.resultsSelector.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)

        app.appearancePopup.selectItem(withTitle: "System")
        app.changeAppearance()
        XCTAssertNil(NSApp.appearance)
        XCTAssertEqual(defaults.string(forKey: "appearancePreference"), "system")
    }

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
            let resultsHeight = app.resultsContainer.frame.height
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
            XCTAssertEqual(app.resultsSelector.selectedSegment, 1)
            XCTAssertEqual(app.resultsContainer.frame.height, resultsHeight, accuracy: 1)
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
            XCTAssertEqual(app.resultsSelector.selectedSegment, 2)
            XCTAssertEqual(app.resultsContainer.frame.height, resultsHeight, accuracy: 1)
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
