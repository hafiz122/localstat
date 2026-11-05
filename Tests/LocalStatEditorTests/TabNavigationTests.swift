import AppKit
import XCTest
@testable import LocalStat
import SASCore

final class TabNavigationTests: XCTestCase {
    @MainActor private func makeApp() throws -> AppDelegate {
        _ = NSApplication.shared
        let suite = "LocalStatTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let app = AppDelegate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStatTabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app.projectURL = folder
        app.appearanceDefaults = defaults
        app.buildMenu(); app.buildWindow()
        addTeardownBlock { @MainActor in
            app.settingsController?.close()
            app.window.delegate = nil; app.window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        return app
    }

    @MainActor private func answerAlerts(_ titles: [String]) -> Timer {
        var remaining = titles
        let deadline = Date().addingTimeInterval(5)
        let timer = Timer(timeInterval: 0.01, repeats: true) { timer in
            MainActor.assumeIsolated {
                if let title = remaining.first, let content = NSApp.modalWindow?.contentView,
                   let response = button(title, in: content) {
                    remaining.removeFirst()
                    response.performClick(nil)
                    if remaining.isEmpty { timer.invalidate() }
                } else if Date() > deadline {
                    XCTFail("Did not find modal response: \(remaining)")
                    NSApp.abortModal(); timer.invalidate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        return timer
    }

    @MainActor func testCloseButtonsKeepInactiveDocumentSelection() throws {
        let app = try makeApp()
        let first = EditorDocument(url: URL(fileURLWithPath: "/tmp/first.sas"), source: "data first; run;")
        let second = EditorDocument(url: URL(fileURLWithPath: "/tmp/second.sas"), source: "data second; run;")
        app.addDocument(first); app.addDocument(second)
        let selected = NSRange(location: 5, length: 6)
        second.textView.setSelectedRange(selected)
        let close = try XCTUnwrap(button("Close first.sas", in: app.window.contentView!))
        XCTAssertFalse(close.isHidden)
        XCTAssertEqual(close.toolTip, "Close first.sas")
        close.performClick(nil)
        XCTAssertEqual(app.documents.map(\.id), [second.id])
        XCTAssertEqual(app.current?.id, second.id)
        XCTAssertEqual(second.textView.selectedRange(), selected)
        XCTAssertEqual(second.textView.string, "data second; run;")
        XCTAssertFalse(second.isDirty)
    }

    @MainActor func testFontMenuCommandsSelectAndFocusExistingSettings() throws {
        let app = try makeApp()
        let original = app.preferences.values
        let stored = app.preferences.defaults.data(forKey: "idePreferences")
        let menu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
        let editor = try XCTUnwrap(menu.item(withTitle: "Editor Font…"))
        menu.performActionForItem(at: menu.index(of: editor))
        let settings = try XCTUnwrap(app.settingsController)
        XCTAssertEqual(settings.sections.selectedTabViewItem?.identifier as? String, "Editor")
        XCTAssertEqual((settings.window?.firstResponder as? NSView)?.identifier?.rawValue, "editorFontName")
        let output = try XCTUnwrap(menu.item(withTitle: "Output Font…"))
        menu.performActionForItem(at: menu.index(of: output))
        XCTAssertTrue(app.settingsController === settings)
        XCTAssertEqual(settings.sections.selectedTabViewItem?.identifier as? String, "Output and Tables")
        XCTAssertEqual((settings.window?.firstResponder as? NSView)?.identifier?.rawValue, "outputFontName")
        XCTAssertEqual(app.preferences.values, original)
        XCTAssertEqual(app.preferences.defaults.data(forKey: "idePreferences"), stored)
        settings.close()
        menu.performActionForItem(at: menu.index(of: output))
        XCTAssertTrue(app.settingsController === settings)
        XCTAssertTrue(settings.window?.isVisible ?? false)
        XCTAssertEqual(settings.sections.selectedTabViewItem?.identifier as? String, "Output and Tables")
    }

    @MainActor func testClosingActiveTabsSelectsRightThenLeftAndEndsEmpty() throws {
        let app = try makeApp()
        let documents = ["first", "middle", "last"].map {
            EditorDocument(url: app.projectURL.appendingPathComponent("\($0).sas"), source: "data \($0); run;")
        }
        documents.forEach(app.addDocument)
        app.tabs.selectTabViewItem(withIdentifier: documents[1].id)
        try XCTUnwrap(button("Close middle.sas", in: app.window.contentView!)).performClick(nil)
        XCTAssertEqual(app.current?.id, documents[2].id)
        try XCTUnwrap(button("Close last.sas", in: app.window.contentView!)).performClick(nil)
        XCTAssertEqual(app.current?.id, documents[0].id)
        app.closeWindowOrDocument(app.window)
        XCTAssertTrue(app.documents.isEmpty)
        XCTAssertEqual(app.tabs.numberOfTabViewItems, 0)
        XCTAssertNil(app.current)
        XCTAssertFalse(app.runButton.isEnabled)
        XCTAssertTrue(app.statusLabel.stringValue.hasPrefix("No programs open."))
    }

    @MainActor func testDirtyInactiveCloseCancelAndDiscardKeepSelectedEditorState() throws {
        let app = try makeApp()
        let dirty = EditorDocument(url: app.projectURL.appendingPathComponent("dirty.sas"), source: "data changed; run;")
        dirty.savedSource = ""
        let source = (0..<100).map { "x\($0)=\($0);" }.joined(separator: "\n")
        let survivor = EditorDocument(url: nil, source: source)
        app.addDocument(dirty); app.addDocument(survivor)
        survivor.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        survivor.textView.undoManager?.beginUndoGrouping()
        survivor.textView.insertText("\n/* keep */", replacementRange: survivor.textView.selectedRange())
        survivor.textView.undoManager?.endUndoGrouping()
        survivor.textView.scrollRangeToVisible(survivor.textView.selectedRange())
        let selection = survivor.textView.selectedRange()
        let origin = survivor.scrollView.contentView.bounds.origin
        let edited = survivor.textView.string
        for choice in ["Cancel", "Discard Changes"] {
            let timer = answerAlerts([choice])
            try XCTUnwrap(button("Close dirty.sas", in: app.window.contentView!)).performClick(nil)
            timer.invalidate()
            XCTAssertEqual(app.current?.id, survivor.id)
            XCTAssertEqual(survivor.textView.string, edited)
            XCTAssertEqual(survivor.textView.selectedRange(), selection)
            XCTAssertEqual(survivor.scrollView.contentView.bounds.origin.y, origin.y, accuracy: 1)
            XCTAssertTrue(survivor.textView.undoManager?.canUndo ?? false)
            XCTAssertTrue(survivor.isDirty)
            XCTAssertEqual(app.documents.count, choice == "Cancel" ? 2 : 1)
        }
        survivor.textView.undoManager?.undo()
        XCTAssertEqual(survivor.textView.string, source)
        XCTAssertFalse(survivor.isDirty)
    }

    @MainActor func testSaveOnCloseWritesTheDirtyBuffer() throws {
        let app = try makeApp()
        let url = app.projectURL.appendingPathComponent("saved.sas")
        try "old source".write(to: url, atomically: true, encoding: .utf8)
        let document = EditorDocument(url: url, source: "data saved; run;")
        document.savedSource = "old source"
        app.addDocument(document)
        let timer = answerAlerts(["Save"])
        defer { timer.invalidate() }
        try XCTUnwrap(button("Close saved.sas", in: app.window.contentView!)).performClick(nil)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "data saved; run;")
        XCTAssertTrue(app.documents.isEmpty)
    }

    @MainActor func testFailedSaveKeepsTheDirtyTabAndPreviousSelection() throws {
        let app = try makeApp()
        let document = EditorDocument(url: app.projectURL.appendingPathComponent("missing/failed.sas"), source: "data failed; run;")
        document.savedSource = ""
        let survivor = EditorDocument(url: nil, source: "data survivor; run;")
        app.addDocument(document); app.addDocument(survivor)
        let timer = answerAlerts(["Save", "OK"])
        defer { timer.invalidate() }
        try XCTUnwrap(button("Close failed.sas", in: app.window.contentView!)).performClick(nil)
        XCTAssertEqual(app.documents.count, 2)
        XCTAssertEqual(app.current?.id, survivor.id)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.textView.string, "data failed; run;")
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.url!.path))
    }

    @MainActor func testTabOverflowKeepsSelectedLongFilenameAndCloseButtonVisible() throws {
        let app = try makeApp()
        app.window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 540), display: false)
        for index in 0..<12 {
            app.addDocument(EditorDocument(url: app.projectURL.appendingPathComponent("\(index)-" + String(repeating: "long-name-", count: 10) + ".sas"), source: "data d; run;"))
        }
        app.window.contentView?.layoutSubtreeIfNeeded()
        let strip = app.programTabStrip
        XCTAssertGreaterThan(try XCTUnwrap(strip.documentView).frame.width, strip.contentSize.width)
        let last = try XCTUnwrap(app.current)
        let close = try XCTUnwrap(button("Close \(last.url!.lastPathComponent)", in: strip))
        XCTAssertTrue(close.isEnabled)
        XCTAssertGreaterThanOrEqual(close.frame.width, 24)
        let visible = strip.contentView.bounds
        XCTAssertTrue(visible.contains(close.convert(close.bounds, to: strip.documentView)))
        let first = try XCTUnwrap(app.documents.first)
        app.tabs.selectTabViewItem(withIdentifier: first.id)
        app.window.contentView?.layoutSubtreeIfNeeded()
        let firstClose = try XCTUnwrap(button("Close \(first.url!.lastPathComponent)", in: strip))
        XCTAssertTrue(strip.contentView.bounds.contains(firstClose.convert(firstClose.bounds, to: strip.documentView)))
        XCTAssertGreaterThanOrEqual(app.tabs.frame.height, 160)
        XCTAssertGreaterThanOrEqual(app.resultsContainer.frame.height, 140)
    }

    @MainActor func testTabTitlesHaveReadableContrastInBothAppearances() throws {
        let app = try makeApp()
        app.addDocument(EditorDocument(url: nil, source: "data first; run;"))
        app.addDocument(EditorDocument(url: nil, source: "data second; run;"))
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.sRGB)!
            let linear = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                let value = Double($0)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let titles = buttons(in: app.programTabStrip).filter { $0.title != "×" }
        XCTAssertEqual(titles.count, 2)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for title in titles {
                let color = try XCTUnwrap(title.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                appearance.performAsCurrentDrawingAppearance {
                    let foreground = luminance(color)
                    let background = luminance(app.programTabStrip.usesStudioStyle
                        ? (title.state == .on ? .white : StudioStyle.chrome)
                        : (title.state == .on ? .controlBackgroundColor : .windowBackgroundColor))
                    XCTAssertGreaterThanOrEqual((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05), 4.5)
                }
            }
        }
    }

    @MainActor func testClosingExecutingDocumentKeepsItsRunAndDiagnosticsSnapshot() async throws {
        let app = try makeApp()
        let executable = app.projectURL.appendingPathComponent("runtime")
        try "#!/bin/sh\nsleep 0.3\nprintf 'kept output\\n'\nprintf 'ERROR(L1): sample diagnostic\\n' >&2\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        app.runner = LocalRuntimeRunner(executable: executable)
        let document = EditorDocument(url: nil, source: "data original; run;")
        app.addDocument(document)
        app.runProgram()
        for _ in 0..<100 {
            if app.runner.isRunning { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(app.runner.isRunning)
        try XCTUnwrap(button("Close Untitled.sas", in: app.window.contentView!)).performClick(nil)
        XCTAssertTrue(app.runner.isRunning)
        for _ in 0..<250 {
            if app.lastResult != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let result = try XCTUnwrap(app.lastResult)
        XCTAssertEqual(result.output, "kept output\n")
        XCTAssertEqual(result.request.source, "data original; run;")
        XCTAssertTrue(app.documents.isEmpty)
        app.diagnosticTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        app.goToDiagnostic()
        XCTAssertTrue(app.statusLabel.stringValue.contains("closed since this run"))
    }
}

@MainActor private func button(_ label: String, in view: NSView) -> NSButton? {
    if let button = view as? NSButton, button.accessibilityLabel() == label || button.title == label { return button }
    for child in view.subviews {
        if let found = button(label, in: child) { return found }
    }
    return nil
}
