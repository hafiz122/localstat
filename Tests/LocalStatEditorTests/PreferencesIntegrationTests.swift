import AppKit
import WebKit
import XCTest
@testable import LocalStat
import SASCore

final class PreferencesIntegrationTests: XCTestCase {
    @MainActor func testSettingsShowsRoundedTableZoom() throws {
        _ = NSApplication.shared
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildWindow(); app.showSettings()
        defer { app.settingsController?.close(); app.window.delegate = nil; app.window.close() }
        let settings = try XCTUnwrap(app.settingsController)
        settings.sections.selectTabViewItem(at: 2)
        func zoomPopup(in view: NSView) -> NSPopUpButton? {
            if view.identifier?.rawValue == "tableZoom" { return view as? NSPopUpButton }
            return view.subviews.lazy.compactMap { zoomPopup(in: $0) }.first
        }
        app.preferences.update { $0.tableZoom = 2 }
        for _ in 0..<2 { app.preferences.update { $0.tableZoom -= 0.1 } }
        XCTAssertEqual(try XCTUnwrap(zoomPopup(in: settings.sections)).titleOfSelectedItem, "180%")
    }

    @MainActor func testHelpClearsEmptySearchStateWhenNavigating() throws {
        _ = NSApplication.shared
        let help = try HelpWindowController(preferences: isolatedPreferences())
        defer { help.close() }
        help.searchField.stringValue = "impossibleword-123"
        help.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: help.searchField))
        XCTAssertEqual(help.contents.numberOfRows, 0)
        help.showArticle("projects")
        XCTAssertEqual(help.searchField.stringValue, "")
        XCTAssertEqual(help.contents.numberOfRows, help.library.articles.count)
        func visibleEmptyMessage(in view: NSView) -> Bool {
            if let text = view as? NSTextField, text.stringValue == "No matching articles.", !text.isHidden { return true }
            return view.subviews.contains { visibleEmptyMessage(in: $0) }
        }
        XCTAssertFalse(visibleEmptyMessage(in: try XCTUnwrap(help.window?.contentView)))
    }

    @MainActor func testHelpNavigationKeepsTheRequestedArticleAfterFilteredSelection() throws {
        _ = NSApplication.shared
        let help = try HelpWindowController(preferences: isolatedPreferences())
        defer { help.close() }
        help.searchField.stringValue = "STREAMINIT"
        help.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: help.searchField))
        help.contents.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(help.currentArticle?.id, "reference")
        help.showArticle("compatibility")
        XCTAssertEqual(help.currentArticle?.id, "compatibility")
        XCTAssertEqual(help.contents.selectedRow, help.library.articles.firstIndex { $0.id == "compatibility" })
    }

    @MainActor func testAppearanceChangePreservesHorizontalScroll() throws {
        _ = NSApplication.shared
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildWindow()
        defer { app.window.delegate = nil; app.window.close() }
        let source = "title '" + String(repeating: "long source text ", count: 50) + "';"
        let document = EditorDocument(url: nil, source: source); app.addDocument(document)
        let editor = document.textView
        editor.layoutManager?.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        editor.sizeToFit()
        editor.scrollRangeToVisible(NSRange(location: (source as NSString).length, length: 0))
        let origin = document.scrollView.contentView.bounds.origin
        XCTAssertGreaterThan(origin.x, 100)
        app.preferences.update { $0.theme = .paper }
        XCTAssertEqual(document.scrollView.contentView.bounds.origin.x, origin.x, accuracy: 1)
    }

    @MainActor func testIncreaseSizeKeyboardEquivalent() throws {
        _ = NSApplication.shared
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildMenu(); app.buildWindow()
        app.addDocument(EditorDocument(url: nil, source: "data d; run;"))
        defer { app.window.delegate = nil; app.window.close() }
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                                 windowNumber: app.window.windowNumber, context: nil, characters: "+", charactersIgnoringModifiers: "+", isARepeat: false, keyCode: 24))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(app.preferences.values.editorFontSize, 14)
    }

    @MainActor func testThemeTextContrastInBothAppearances() throws {
        _ = NSApplication.shared
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                func rgb(_ color: NSColor, on background: NSColor) -> [Double] {
                    let c = color.usingColorSpace(.sRGB)!, b = background.usingColorSpace(.sRGB)!
                    let a = Double(c.alphaComponent)
                    let foreground: [Double] = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
                    let backdrop: [Double] = [Double(b.redComponent), Double(b.greenComponent), Double(b.blueComponent)]
                    return zip(foreground, backdrop).map { foreground, background in
                        foreground * a + background * (1 - a)
                    }
                }
                func luminance(_ channels: [Double]) -> Double {
                    let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
                }
                for theme in EditorTheme.allCases {
                    let palette = theme.palette
                    for background in [palette.background, palette.currentLine] {
                        let bg = luminance(rgb(background, on: palette.background))
                        for foreground in [palette.text, palette.keyword, palette.string, palette.comment] {
                            let fg = luminance(rgb(foreground, on: background))
                            let ratio = (max(bg, fg) + 0.05) / (min(bg, fg) + 0.05)
                            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.title) in \(name.rawValue): \(ratio)")
                        }
                    }
                    let bg = luminance(rgb(palette.selection, on: palette.background))
                    let fg = luminance(rgb(palette.selectedText, on: palette.selection))
                    XCTAssertGreaterThanOrEqual((max(bg, fg) + 0.05) / (min(bg, fg) + 0.05), 4.5)
                }
            }
        }
    }

    @MainActor private func isolatedPreferences() throws -> IDEPreferences {
        let suite = "LocalStatPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return IDEPreferences(defaults: defaults)
    }

    @MainActor func testSASNativeIsStartupDefaultAndPreservesExplicitSystemChoice() throws {
        let preferences = try isolatedPreferences()
        XCTAssertEqual(preferences.values.appearance, .sasStudio)
        XCTAssertEqual(preferences.values.theme, .sasStudio)
        XCTAssertEqual(preferences.values.appearance.title, "SAS Native")
        XCTAssertEqual(preferences.values.theme.title, "SAS Native")

        preferences.update { $0.appearance = .system; $0.theme = .native }
        let reopened = IDEPreferences(defaults: preferences.defaults)
        XCTAssertEqual(reopened.values.appearance, .system)
        XCTAssertEqual(reopened.values.theme, .native)
    }

    @MainActor func testPreferenceMigrationPersistenceAndSectionReset() throws {
        let preferences = try isolatedPreferences()
        preferences.defaults.set("dark", forKey: "appearancePreference")
        preferences.defaults.set(260, forKey: "navigatorWidth")
        preferences.defaults.set("/my/project", forKey: "projectFolder")
        preferences.reload()
        XCTAssertEqual(preferences.values.appearance, .dark)
        XCTAssertEqual(preferences.values.navigatorWidth, 260)
        preferences.update {
            $0.editorFontName = "Menlo-Regular"; $0.editorFontSize = 19; $0.theme = .paper
            $0.outputFontSize = 16; $0.indentWidth = 4; $0.helpFontSize = 18
        }
        let reopened = IDEPreferences(defaults: preferences.defaults)
        XCTAssertEqual(reopened.values, preferences.values)
        reopened.reset("Layout")
        XCTAssertEqual(reopened.values.navigatorWidth, 235)
        XCTAssertEqual(reopened.values.editorFontSize, 19)
        XCTAssertEqual(reopened.values.appearance, .dark)
        XCTAssertEqual(reopened.defaults.string(forKey: "projectFolder"), "/my/project")
        reopened.update { $0.editorFontName = "missing-font-123"; $0.editorFontSize = .infinity; $0.tableZoom = 7 }
        XCTAssertEqual(reopened.values.editorFont.pointSize, 13)
        XCTAssertEqual(reopened.values.tableZoom, 2)
    }

    @MainActor func testLiveEditorPreferencesKeepSourceSelectionUndoAndFont() throws {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildWindow()
        defer { app.window.delegate = nil; app.window.close(); NSApp.appearance = originalAppearance }
        let source = "data demo;\n" + (1...100).map { "  x\($0)=\($0);" }.joined(separator: "\n") + "\nrun;"
        let document = EditorDocument(url: nil, source: source)
        app.addDocument(document)
        let editor = document.textView
        editor.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        editor.undoManager?.beginUndoGrouping()
        editor.insertText("\n/* café 😀 */", replacementRange: editor.selectedRange())
        editor.undoManager?.endUndoGrouping()
        let edited = editor.string
        let selected = editor.selectedRange()
        let canUndo = editor.undoManager?.canUndo
        editor.scrollRangeToVisible(selected)
        let origin = document.scrollView.contentView.bounds.origin
        app.preferences.update {
            $0.editorFontName = "Menlo-Regular"; $0.editorFontSize = 19; $0.lineSpacing = 1.5
            $0.editorWrap = true; $0.lineNumbers = false; $0.invisibleCharacters = true
            $0.currentLineHighlight = true; $0.theme = .midnight
        }
        XCTAssertEqual(editor.string, edited)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(editor.undoManager?.canUndo, canUndo)
        XCTAssertEqual(document.scrollView.contentView.bounds.origin.y, origin.y, accuracy: 1)
        XCTAssertTrue(document.isDirty)
        XCTAssertTrue(editor.textContainer?.widthTracksTextView ?? false)
        XCTAssertFalse(document.scrollView.rulersVisible)
        XCTAssertTrue(editor.layoutManager?.showsInvisibleCharacters ?? false)
        document.highlight()
        XCTAssertEqual((editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 19)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, source)
        XCTAssertFalse(document.isDirty)
        let newDocument = EditorDocument(url: nil, source: "proc print; run;")
        app.addDocument(newDocument)
        XCTAssertEqual((newDocument.textView.typingAttributes[.font] as? NSFont)?.pointSize, 19)
    }

    @MainActor func testEditingAssistanceUsesPreferences() {
        _ = NSApplication.shared
        let document = EditorDocument(url: nil, source: "")
        var preferences = PreferenceValues()
        preferences.bracketPairing = false
        preferences.automaticIndentation = false
        document.applyPreferences(preferences)
        document.textView.insertText("(", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.textView.string, "(")
        document.textView.string = "  do;"
        document.textView.setSelectedRange(NSRange(location: 5, length: 0))
        document.textView.insertNewline(nil)
        XCTAssertEqual(document.textView.string, "  do;\n")
        for width in [2, 4, 8] {
            preferences.indentWidth = width; preferences.automaticIndentation = true
            document.applyPreferences(preferences)
            document.textView.string = "do;"
            document.textView.setSelectedRange(NSRange(location: 3, length: 0))
            document.textView.insertNewline(nil)
            XCTAssertEqual(document.textView.string, "do;\n" + String(repeating: " ", count: width))
            document.textView.insertBacktab(nil)
            XCTAssertEqual(document.textView.string, "do;\n")
        }
    }

    @MainActor func testHelpLibrarySearchAndExampleOpening() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let library = try DocumentationLibrary.bundled()
        XCTAssertTrue(library.search("ordinary least squares").contains { $0.id == "regression" })
        XCTAssertTrue(library.search("CALL STREAMINIT").contains { $0.id == "reference" })
        XCTAssertTrue(library.search("PROC STANDARD").contains { $0.id == "reference" })
        XCTAssertTrue(library.search("impossibleword-123").isEmpty)
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildWindow()
        app.showHelp()
        let help = try XCTUnwrap(app.helpController)
        defer { help.close(); app.window.delegate = nil; app.window.close() }
        app.showHelp()
        XCTAssertTrue(app.helpController === help)
        help.showArticle("data-steps")
        for _ in 0..<250 {
            if help.loadedArticleID == "data-steps" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let title = try await help.webView.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "DATA steps and variables")
        help.openCode()
        XCTAssertEqual(app.documents.count, 1)
        XCTAssertNil(app.current?.url)
        XCTAssertTrue(app.current?.isDirty ?? false)
        XCTAssertTrue(app.current?.textView.string.contains("passed=") ?? false)
        help.window?.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        help.showFind()
        app.closeWindowOrDocument(help.window)
        XCTAssertFalse(help.window?.isVisible ?? true)
        XCTAssertEqual(app.documents.count, 1)
    }

    @MainActor func testSettingsWindowAndContextualSizeCommands() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let preferences = try isolatedPreferences()
        let app = AppDelegate(); app.appearanceDefaults = preferences.defaults; app.buildMenu(); app.buildWindow()
        app.addDocument(EditorDocument(url: nil, source: "data d; run;"))
        app.window.makeKeyAndOrderFront(nil)
        defer { app.settingsController?.close(); app.window.delegate = nil; app.window.close() }
        app.window.makeFirstResponder(app.outputView)
        app.increaseSize()
        XCTAssertEqual(app.preferences.values.outputFontSize, 13)
        XCTAssertEqual(app.preferences.values.editorFontSize, 13)
        app.window.makeFirstResponder(app.current?.textView)
        app.increaseSize()
        XCTAssertEqual(app.preferences.values.editorFontSize, 14)
        app.showSettings()
        try await Task.sleep(nanoseconds: 100_000_000)
        let settings = try XCTUnwrap(app.settingsController)
        XCTAssertEqual(settings.sections.numberOfTabViewItems, 5)
        app.showSettings()
        XCTAssertTrue(settings === app.settingsController)
        app.closeWindowOrDocument(settings.window)
        XCTAssertFalse(settings.window?.isVisible ?? true)
        XCTAssertEqual(app.documents.count, 1)
    }

    @MainActor func testTableZoomPreservesPaginationAndPrintGeometry() throws {
        _ = NSApplication.shared
        let table = ResultTable(procedure: "PRINT", title: "Demo", headers: [ResultRow(cells: [ResultCell("x")])],
                                rows: (0..<100).map { ResultRow(cells: [ResultCell("\($0)")]) })
        let view = TableDocumentView(tables: [table])
        let pages = view.pageCount, size = view.frame.size, firstPage = view.rectForPage(1)
        view.setScreenZoom(1.7)
        XCTAssertEqual(view.pageCount, pages)
        XCTAssertEqual(view.rectForPage(1), firstPage)
        XCTAssertEqual(view.frame.width, size.width * 1.7, accuracy: 0.1)
        XCTAssertEqual(view.bounds.width, size.width, accuracy: 0.001)
        XCTAssertEqual(view.bounds.height, size.height, accuracy: 0.001)
        let printView = try XCTUnwrap(TablePrintRenderer.operation(for: [table]).view as? TableDocumentView)
        let printSize = printView.frame.size
        printView.setScreenZoom(2)
        XCTAssertEqual(printView.screenZoom, 1)
        XCTAssertEqual(printView.frame.size, printSize)
    }
}
