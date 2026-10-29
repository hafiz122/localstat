import Foundation

public struct EditorTextEdit: Equatable {
    public let replacementRange: NSRange
    public let replacement: String
    public let selectedRange: NSRange

    public init(replacementRange: NSRange, replacement: String, selectedRange: NSRange) {
        self.replacementRange = replacementRange
        self.replacement = replacement
        self.selectedRange = selectedRange
    }
}

public enum EditorTextEditing {
    public static let indentUnit = "  "
    private static let bracketPairs = ["(": ")", "[": "]", "{": "}"]

    public static func openingBracket(_ bracket: String, in source: String, selection: NSRange) -> EditorTextEdit? {
        guard let closing = bracketPairs[bracket], isValid(selection, in: source) else { return nil }
        let selected = (source as NSString).substring(with: selection)
        return EditorTextEdit(
            replacementRange: selection,
            replacement: bracket + selected + closing,
            selectedRange: NSRange(location: selection.location + 1, length: selection.length)
        )
    }

    public static func closingBracket(_ bracket: String, in source: String, selection: NSRange) -> EditorTextEdit? {
        let text = source as NSString
        guard bracketPairs.values.contains(bracket), selection.length == 0,
              isValid(selection, in: source), selection.location < text.length,
              text.substring(with: NSRange(location: selection.location, length: 1)) == bracket else { return nil }
        return EditorTextEdit(
            replacementRange: selection,
            replacement: "",
            selectedRange: NSRange(location: selection.location + 1, length: 0)
        )
    }

    public static func deleteBackward(in source: String, selection: NSRange) -> EditorTextEdit? {
        let text = source as NSString
        guard selection.length == 0, isValid(selection, in: source), selection.location > 0,
              selection.location < text.length else { return nil }
        let opening = text.substring(with: NSRange(location: selection.location - 1, length: 1))
        let closing = text.substring(with: NSRange(location: selection.location, length: 1))
        guard bracketPairs[opening] == closing else { return nil }
        return EditorTextEdit(
            replacementRange: NSRange(location: selection.location - 1, length: 2),
            replacement: "",
            selectedRange: NSRange(location: selection.location - 1, length: 0)
        )
    }

    public static func newline(in source: String, selection: NSRange) -> EditorTextEdit? {
        guard isValid(selection, in: source) else { return nil }
        let text = source as NSString
        let prefix = text.substring(to: selection.location) as NSString
        let newline = prefix.range(of: "\n", options: .backwards)
        let lineStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        let linePrefix = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let leading = leadingWhitespace(in: linePrefix)
        let statement = linePrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var nextIndent = leading
        if opensIndentedBlock(statement) {
            nextIndent += indentUnit
        } else if closesIndentedBlock(statement) {
            nextIndent = removingOneIndent(from: leading)
        }

        let following = selection.location < text.length
            ? text.substring(with: NSRange(location: selection.location, length: 1))
            : ""
        let preceding = selection.location > 0
            ? text.substring(with: NSRange(location: selection.location - 1, length: 1))
            : ""
        let closesPair = bracketPairs[preceding] == following
        let replacement = closesPair
            ? "\n" + leading + indentUnit + "\n" + leading
            : "\n" + nextIndent
        let caretOffset = closesPair
            ? 1 + (leading as NSString).length + (indentUnit as NSString).length
            : (replacement as NSString).length
        return EditorTextEdit(
            replacementRange: selection,
            replacement: replacement,
            selectedRange: NSRange(location: selection.location + caretOffset, length: 0)
        )
    }

    public static func indent(in source: String, selection: NSRange) -> EditorTextEdit? {
        guard isValid(selection, in: source) else { return nil }
        if selection.length == 0 {
            return EditorTextEdit(
                replacementRange: selection,
                replacement: indentUnit,
                selectedRange: NSRange(location: selection.location + (indentUnit as NSString).length, length: 0)
            )
        }
        let text = source as NSString
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        let replacement = mapLines(original) { indentUnit + $0 }
        return EditorTextEdit(
            replacementRange: lines,
            replacement: replacement,
            selectedRange: NSRange(location: lines.location, length: (replacement as NSString).length)
        )
    }

    public static func outdent(in source: String, selection: NSRange) -> EditorTextEdit? {
        guard isValid(selection, in: source) else { return nil }
        let text = source as NSString
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        var removedFromFirstLine = 0
        var lineIndex = 0
        let replacement = mapLines(original) { line in
            let result = removingOneIndent(from: line)
            if lineIndex == 0 { removedFromFirstLine = (line as NSString).length - (result as NSString).length }
            lineIndex += 1
            return result
        }
        guard replacement != original else { return nil }
        let selectedRange: NSRange
        if selection.length == 0 {
            selectedRange = NSRange(
                location: max(lines.location, selection.location - removedFromFirstLine),
                length: 0
            )
        } else {
            selectedRange = NSRange(location: lines.location, length: (replacement as NSString).length)
        }
        return EditorTextEdit(replacementRange: lines, replacement: replacement, selectedRange: selectedRange)
    }

    private static func opensIndentedBlock(_ statement: String) -> Bool {
        statement.hasPrefix("data ") || statement.hasPrefix("proc ") || statement == "do;" ||
            statement.hasPrefix("do ") || statement.hasSuffix(" do;") || statement == "select;" ||
            statement.hasPrefix("select ") ||
            ["(", "[", "{"].contains(where: statement.hasSuffix)
    }

    private static func closesIndentedBlock(_ statement: String) -> Bool {
        statement.hasPrefix("end;") || statement.hasPrefix("run;") || statement.hasPrefix("quit;")
    }

    private static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func removingOneIndent(from line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = min(indentUnit.count, line.prefix { $0 == " " }.count)
        return String(line.dropFirst(spaces))
    }

    private static func mapLines(_ source: String, transform: (String) -> String) -> String {
        let parts = source.components(separatedBy: "\n")
        return parts.enumerated().map { index, line in
            index == parts.count - 1 && line.isEmpty ? line : transform(line)
        }.joined(separator: "\n")
    }

    private static func isValid(_ range: NSRange, in source: String) -> Bool {
        range.location != NSNotFound && range.location >= 0 && range.length >= 0 &&
            NSMaxRange(range) <= (source as NSString).length
    }
}
