import AppKit
import XCTest
@testable import LocalStat

final class IndentationDefaultsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "LocalStatIndentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor func testFreshPreferencesAndEditorUseFourSpaces() throws {
        _ = NSApplication.shared
        let preferences = IDEPreferences(defaults: try defaults())
        XCTAssertEqual(preferences.values.indentWidth, 4)
        let editor = CodeTextView(frame: .zero)
        XCTAssertEqual(editor.indentWidth, 4)
        let document = EditorDocument(url: nil, source: "data demo;")
        document.applyPreferences(preferences.values)
        document.textView.setSelectedRange(NSRange(location: 10, length: 0))
        document.textView.insertNewline(nil)
        XCTAssertEqual(document.textView.string, "data demo;\n    ")
        document.textView.insertTab(nil)
        XCTAssertEqual(document.textView.string, "data demo;\n        ")
        document.textView.insertBacktab(nil)
        XCTAssertEqual(document.textView.string, "data demo;\n    ")
    }

    @MainActor func testSavedTwoSpacesMigrateOnceWithoutResettingOtherSettings() throws {
        let defaults = try defaults()
        var saved = PreferenceValues()
        saved.indentWidth = 2
        saved.editorFontSize = 19
        saved.theme = .paper
        saved.automaticIndentation = false
        try defaults.set(JSONEncoder().encode(saved), forKey: "idePreferences")
        let preferences = IDEPreferences(defaults: defaults)
        XCTAssertEqual(preferences.values.indentWidth, 4)
        XCTAssertEqual(preferences.values.editorFontSize, 19)
        XCTAssertEqual(preferences.values.theme, .paper)
        XCTAssertFalse(preferences.values.automaticIndentation)
        let persisted = try JSONDecoder().decode(PreferenceValues.self, from: XCTUnwrap(defaults.data(forKey: "idePreferences")))
        XCTAssertEqual(persisted.indentWidth, 4)
        XCTAssertEqual(IDEPreferences(defaults: defaults).values, preferences.values)
        preferences.update { $0.indentWidth = 2 }
        XCTAssertEqual(IDEPreferences(defaults: defaults).values.indentWidth, 2,
                       "A two-space choice made after upgrading must survive reopening")
    }

    @MainActor func testSavedFourAndEightSpaceChoicesArePreserved() throws {
        for width in [4, 8] {
            let defaults = try defaults()
            var saved = PreferenceValues()
            saved.indentWidth = width
            try defaults.set(JSONEncoder().encode(saved), forKey: "idePreferences")
            XCTAssertEqual(IDEPreferences(defaults: defaults).values.indentWidth, width)
        }
    }

    @MainActor func testInvalidWidthAndEditingResetUseFourSpaces() throws {
        var values = PreferenceValues()
        values.indentWidth = 3
        values.validate()
        XCTAssertEqual(values.indentWidth, 4)
        let preferences = IDEPreferences(defaults: try defaults())
        preferences.update {
            $0.indentWidth = 8
            $0.automaticIndentation = false
            $0.bracketPairing = false
        }
        preferences.reset("Editing")
        XCTAssertEqual(preferences.values.indentWidth, 4)
        XCTAssertTrue(preferences.values.automaticIndentation)
        XCTAssertTrue(preferences.values.bracketPairing)
    }
}
