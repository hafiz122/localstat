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

        XCTAssertEqual(app.navigatorPane.frame.width, 235, accuracy: 2)
        let initialFraction = app.resultsContainer.frame.height / app.editorResultsSplit.bounds.height
        XCTAssertEqual(initialFraction, 0.38, accuracy: 0.03)
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

        reopenedApp.navigatorSplit.setPosition(500, ofDividerAt: 0)
        reopenedApp.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(reopenedApp.editorResultsSplit.frame.width, 510)
        XCTAssertLessThanOrEqual(reopenedApp.expandResultsButton.frame.maxX, reopenedApp.resultsContainer.bounds.maxX)
        reopenedApp.editorResultsSplit.setPosition(50, ofDividerAt: 0)
        reopenedApp.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(reopenedApp.tabs.frame.height, 160)

        reopenedApp.resultsSelector.selectedSegment = 2
        reopenedApp.changeResultsView()
        XCTAssertEqual(reopenedApp.results.selectedTabViewItem?.identifier as? String, "diagnostics")
        XCTAssertFalse(reopenedApp.diagnosticsEmptyLabel.isHidden)
        XCTAssertEqual(reopenedApp.diagnosticsEmptyLabel.stringValue, "Run a program to see diagnostics here.")
    }

    @MainActor func testFreshStartupKeepsExamplesOutOfProjectExplorer() throws {
        _ = NSApplication.shared
        let suite = "LocalStatFreshProject.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let examples = support.appendingPathComponent("LocalStat/Examples")
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        try "data example; run;".write(to: examples.appendingPathComponent("example.sas"), atomically: true, encoding: .utf8)
        let app = AppDelegate()
        app.appearanceDefaults = defaults
        app.applicationSupportDirectoryOverride = support
        app.buildWindow()
        defer {
            app.window.delegate = nil
            app.window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }

        app.loadProject()
        XCTAssertEqual(app.projectURL.resolvingSymlinksInPath().path,
                       support.appendingPathComponent("LocalStat/Workspace").resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.projectURL.path))
        XCTAssertEqual(app.projectLabel.stringValue, "Workspace")
        XCTAssertTrue(app.projectNodes.isEmpty)
        XCTAssertTrue(app.files.isEmpty)
        XCTAssertEqual(app.fileOutline.numberOfRows, 0)
        XCTAssertTrue(app.documents.isEmpty)
        XCTAssertTrue(app.projectHint.stringValue.contains("Create SAS File"))
        app.newDocument(nil)
        XCTAssertEqual(app.documents.count, 1)
        XCTAssertNil(app.current?.url)
    }

    @MainActor func testStartupRestoresExplicitProjectAndOpensItsProgram() throws {
        _ = NSApplication.shared
        let suite = "LocalStatSavedProject.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let project = support.appendingPathComponent("Chosen Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let program = project.appendingPathComponent("analysis.sas")
        try "data chosen; run;".write(to: program, atomically: true, encoding: .utf8)
        defaults.set(project.path, forKey: "projectFolder")
        let app = AppDelegate()
        app.appearanceDefaults = defaults
        app.applicationSupportDirectoryOverride = support
        app.buildWindow()
        defer {
            app.window.delegate = nil
            app.window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }

        app.loadProject()
        XCTAssertEqual(app.projectURL.resolvingSymlinksInPath().path, project.resolvingSymlinksInPath().path)
        XCTAssertEqual(app.projectLabel.stringValue, "Chosen Project")
        XCTAssertEqual(app.files.map { $0.resolvingSymlinksInPath().path }, [program.resolvingSymlinksInPath().path])
        XCTAssertEqual(app.current?.url?.resolvingSymlinksInPath().path, program.resolvingSymlinksInPath().path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("LocalStat/Workspace").path))
    }

    @MainActor func testStartupFallsBackFromInvalidSavedProjectToEmptyWorkspace() throws {
        _ = NSApplication.shared
        let suite = "LocalStatInvalidProject.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let notAFolder = support.appendingPathComponent("not-a-folder")
        try "file".write(to: notAFolder, atomically: true, encoding: .utf8)
        defaults.set(notAFolder.path, forKey: "projectFolder")
        let app = AppDelegate()
        app.appearanceDefaults = defaults
        app.applicationSupportDirectoryOverride = support
        app.buildWindow()
        defer {
            app.window.delegate = nil
            app.window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }

        app.loadProject()
        XCTAssertEqual(app.projectURL.resolvingSymlinksInPath().path,
                       support.appendingPathComponent("LocalStat/Workspace").resolvingSymlinksInPath().path)
        XCTAssertEqual(app.fileOutline.numberOfRows, 0)
        XCTAssertTrue(app.files.isEmpty)
        XCTAssertTrue(app.documents.isEmpty)
    }

    @MainActor func testProjectNavigatorShowsFoldersAndPreservesExpansion() throws {
        _ = NSApplication.shared
        let app = AppDelegate()
        app.buildWindow()
        defer { app.window.delegate = nil; app.window.close() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStatTree-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("analysis/semester")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "data a; run;".write(to: root.appendingPathComponent("top.sas"), atomically: true, encoding: .utf8)
        try "data b; run;".write(to: nested.appendingPathComponent("nested.sas"), atomically: true, encoding: .utf8)
        try "notes".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.sas"),
                                                    withDestinationURL: nested.appendingPathComponent("nested.sas"))

        app.projectURL = root
        app.refreshProject()
        XCTAssertEqual(app.files.count, 3)
        let folder = try XCTUnwrap(app.projectNodes.first)
        XCTAssertEqual(folder.url.lastPathComponent, "analysis")
        XCTAssertTrue(folder.isDirectory)
        XCTAssertEqual(folder.children.first?.children.first?.url.lastPathComponent, "nested.sas")
        XCTAssertEqual(app.fileOutline.numberOfRows, 4)
        let semester = try XCTUnwrap(folder.children.first)
        app.fileOutline.expandItem(semester)
        XCTAssertEqual(app.fileOutline.numberOfRows, 5)

        app.fileOutline.collapseItem(folder)
        app.refreshProject()
        XCTAssertEqual(app.fileOutline.numberOfRows, 3)
        let refreshedFolder = try XCTUnwrap(app.projectNodes.first)
        XCTAssertFalse(app.fileOutline.isItemExpanded(refreshedFolder))
    }

    @MainActor func testProjectActionsTargetSelectedFolderAndRejectDuplicates() throws {
        _ = NSApplication.shared
        let app = AppDelegate()
        app.buildWindow()
        defer { app.window.delegate = nil; app.window.close() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStatActions-\(UUID().uuidString)")
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStatImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("analysis"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external.appendingPathComponent("samples"), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let sourceFile = external.appendingPathComponent("example.sas")
        try "data example; run;".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "data sample; run;".write(to: external.appendingPathComponent("samples/sample.sas"), atomically: true, encoding: .utf8)

        app.projectURL = root
        app.refreshProject()
        let folder = try XCTUnwrap(app.projectNodes.first)
        app.fileOutline.selectRowIndexes(IndexSet(integer: app.fileOutline.row(forItem: folder)), byExtendingSelection: false)
        XCTAssertEqual(app.selectedProjectFolder, folder.url)

        let newFile = try app.makeProjectFile(named: "new", in: app.selectedProjectFolder)
        XCTAssertEqual(newFile.lastPathComponent, "new.sas")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
        XCTAssertEqual(app.selectedProjectFolder, folder.url)
        XCTAssertThrowsError(try app.makeProjectFile(named: "new.sas", in: folder.url))
        XCTAssertThrowsError(try app.makeProjectFile(named: "../outside", in: folder.url))

        let newFolder = try app.makeProjectFolder(named: "results", in: app.selectedProjectFolder)
        XCTAssertEqual(newFolder.deletingLastPathComponent(), folder.url)
        XCTAssertThrowsError(try app.makeProjectFolder(named: "results", in: folder.url))
        let importedFile = try app.importProjectItem(sourceFile, into: app.selectedProjectFolder)
        XCTAssertEqual(importedFile.deletingLastPathComponent(), folder.url)
        XCTAssertThrowsError(try app.importProjectItem(sourceFile, into: folder.url))
        let importedFolder = try app.importProjectItem(external.appendingPathComponent("samples"), into: folder.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedFolder.appendingPathComponent("sample.sas").path))
        XCTAssertThrowsError(try app.importProjectItem(root, into: folder.url))
        XCTAssertEqual(app.files.count, 3)
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

        XCTAssertEqual(app.appearancePreference, .sasStudio)
        XCTAssertEqual(app.preferences.values.theme, .sasStudio)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        XCTAssertEqual(app.appearancePopup.selectedItem?.title, "SAS Native")
        XCTAssertEqual(app.explorerHeader.stringValue, "Project Explorer")

        app.preferences.update { $0.theme = .native }

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

    @MainActor func testSASNativeGutterFollowsAppAppearance() throws {
        _ = NSApplication.shared
        let suite = "LocalStatGutter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let originalAppearance = NSApp.appearance
        let app = AppDelegate()
        app.appearanceDefaults = defaults
        app.buildWindow()
        defer {
            app.window.delegate = nil
            app.window.close()
            NSApp.appearance = originalAppearance
        }
        let document = EditorDocument(url: nil, source: "data sample; run;")
        app.addDocument(document)
        XCTAssertTrue(document.ruler.usesStudioStyle)
        app.preferences.update { $0.appearance = .dark }
        XCTAssertFalse(document.ruler.usesStudioStyle)
        app.preferences.update { $0.appearance = .sasStudio }
        XCTAssertTrue(document.ruler.usesStudioStyle)
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
            let suiteName = "LocalStatRunTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            app.appearanceDefaults = defaults
            defer { defaults.removePersistentDomain(forName: suiteName) }
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
