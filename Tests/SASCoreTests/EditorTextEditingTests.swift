import Foundation
import XCTest
@testable import SASCore

final class EditorTextEditingTests: XCTestCase {
    private func applying(_ edit: EditorTextEdit, to source: String) -> String {
        (source as NSString).replacingCharacters(in: edit.replacementRange, with: edit.replacement)
    }

    func testOpeningBracketInsertsPairAndPlacesCaretBetweenIt() throws {
        let edit = try XCTUnwrap(EditorTextEditing.openingBracket("(", in: "", selection: NSRange(location: 0, length: 0)))

        XCTAssertEqual(applying(edit, to: ""), "()")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 1, length: 0))
    }

    func testOpeningBracketWrapsSelectedText() throws {
        let source = "model y = x1 x2;"
        let selected = (source as NSString).range(of: "x1 x2")
        let edit = try XCTUnwrap(EditorTextEditing.openingBracket("(", in: source, selection: selected))

        XCTAssertEqual(applying(edit, to: source), "model y = (x1 x2);")
        XCTAssertEqual(edit.selectedRange, NSRange(location: selected.location + 1, length: selected.length))
    }

    func testClosingBracketSkipsExistingCloser() throws {
        let edit = try XCTUnwrap(EditorTextEditing.closingBracket(")", in: "()", selection: NSRange(location: 1, length: 0)))

        XCTAssertEqual(applying(edit, to: "()"), "()")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 2, length: 0))
    }

    func testBackspaceRemovesAnEmptyBracketPair() throws {
        let edit = try XCTUnwrap(EditorTextEditing.deleteBackward(in: "[]", selection: NSRange(location: 1, length: 0)))

        XCTAssertEqual(applying(edit, to: "[]"), "")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 0, length: 0))
    }

    func testReturnPreservesIndentAndIndentsAfterSASDo() throws {
        let source = "  do;"
        let edit = try XCTUnwrap(EditorTextEditing.newline(in: source, selection: NSRange(location: 5, length: 0)))

        XCTAssertEqual(applying(edit, to: source), "  do;\n    ")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 10, length: 0))
    }

    func testReturnIndentsAfterIndexedSASDo() throws {
        let source = "  do die1 = 1 to 6;"
        let edit = try XCTUnwrap(EditorTextEditing.newline(
            in: source,
            selection: NSRange(location: (source as NSString).length, length: 0)
        ))

        XCTAssertEqual(applying(edit, to: source), source + "\n    ")
    }

    func testReturnIndentsAfterSASSelectExpression() throws {
        let source = "select (group);"
        let edit = try XCTUnwrap(EditorTextEditing.newline(
            in: source,
            selection: NSRange(location: (source as NSString).length, length: 0)
        ))

        XCTAssertEqual(applying(edit, to: source), source + "\n  ")
    }

    func testReturnIndentsAfterDataAndProcHeaders() throws {
        for source in ["data demo;", "proc means data=demo;"] {
            let edit = try XCTUnwrap(EditorTextEditing.newline(
                in: source,
                selection: NSRange(location: (source as NSString).length, length: 0)
            ))
            XCTAssertEqual(applying(edit, to: source), source + "\n  ")
        }
    }

    func testReturnDedentsAfterSASEnd() throws {
        let source = "  end;"
        let edit = try XCTUnwrap(EditorTextEditing.newline(in: source, selection: NSRange(location: 6, length: 0)))

        XCTAssertEqual(applying(edit, to: source), "  end;\n")
    }

    func testReturnBetweenBracketsCreatesIndentedBlankLine() throws {
        let source = "  ()"
        let edit = try XCTUnwrap(EditorTextEditing.newline(in: source, selection: NSRange(location: 3, length: 0)))

        XCTAssertEqual(applying(edit, to: source), "  (\n    \n  )")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 8, length: 0))
    }

    func testTabIndentsAndBacktabOutdentsSelectedLines() throws {
        let source = "data demo;\n  x = 1;\nrun;"
        let selection = NSRange(location: 0, length: (source as NSString).length)
        let indented = try XCTUnwrap(EditorTextEditing.indent(in: source, selection: selection))
        let indentedSource = applying(indented, to: source)

        XCTAssertEqual(indentedSource, "  data demo;\n    x = 1;\n  run;")
        let outdented = try XCTUnwrap(EditorTextEditing.outdent(in: indentedSource, selection: indented.selectedRange))
        XCTAssertEqual(applying(outdented, to: indentedSource), source)
    }
}
