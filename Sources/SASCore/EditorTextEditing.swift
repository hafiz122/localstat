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
    public static let defaultIndentWidth = 4
    public static let indentUnit = String(repeating: " ", count: defaultIndentWidth)
    private static let bracketPairs = ["(": ")", "[": "]", "{": "}"]

    public static func openingBracket(_ bracket: String, in source: String, selection: NSRange) -> EditorTextEdit? {
        guard let closing = bracketPairs[bracket], isValid(selection, in: source),
              isCode(in: source, at: selection.location) else { return nil }
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
              isValid(selection, in: source), isCode(in: source, at: selection.location), selection.location < text.length,
              text.substring(with: NSRange(location: selection.location, length: 1)) == bracket else { return nil }
        return EditorTextEdit(
            replacementRange: selection,
            replacement: "",
            selectedRange: NSRange(location: selection.location + 1, length: 0)
        )
    }

    public static func deleteBackward(in source: String, selection: NSRange) -> EditorTextEdit? {
        let text = source as NSString
        guard selection.length == 0, isValid(selection, in: source), isCode(in: source, at: selection.location), selection.location > 0,
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

    public static func newline(in source: String, selection: NSRange, indentWidth: Int = EditorTextEditing.defaultIndentWidth) -> EditorTextEdit? {
        let indentUnit = String(repeating: " ", count: min(max(indentWidth, 1), 8))
        guard isValid(selection, in: source) else { return nil }
        let text = source as NSString
        let prefix = text.substring(to: selection.location) as NSString
        let newline = prefix.range(of: "\n", options: .backwards)
        let lineStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        let linePrefix = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let leading = leadingWhitespace(in: linePrefix)
        let statement = linePrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = isCode(in: source, at: selection.location)
        var nextIndent = leading
        if code && opensIndentedBlock(statement) {
            nextIndent += indentUnit
        } else if code && closesIndentedBlock(statement) {
            nextIndent = removingOneIndent(from: leading, width: indentUnit.count)
        }

        let following = selection.location < text.length
            ? text.substring(with: NSRange(location: selection.location, length: 1))
            : ""
        let preceding = selection.location > 0
            ? text.substring(with: NSRange(location: selection.location - 1, length: 1))
            : ""
        let closesPair = code && selection.length == 0 && bracketPairs[preceding] == following
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

    public static func indent(in source: String, selection: NSRange, indentWidth: Int = EditorTextEditing.defaultIndentWidth) -> EditorTextEdit? {
        let indentUnit = String(repeating: " ", count: min(max(indentWidth, 1), 8))
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

    public static func outdent(in source: String, selection: NSRange, indentWidth: Int = EditorTextEditing.defaultIndentWidth) -> EditorTextEdit? {
        guard isValid(selection, in: source) else { return nil }
        let text = source as NSString
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        var removedFromFirstLine = 0
        var lineIndex = 0
        let replacement = mapLines(original) { line in
            let result = removingOneIndent(from: line, width: min(max(indentWidth, 1), 8))
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

    private static func removingOneIndent(from line: String, width: Int) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = min(width, line.prefix { $0 == " " }.count)
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

    private static func isCode(in source: String, at offset: Int) -> Bool {
        let units = Array(source.utf16.prefix(offset))
        var quote: UInt16?
        var blockComment = false
        var statementComment = false
        var statement = ""
        var rawTerminator: String?
        var rawLine = ""
        var index = 0
        while index < units.count {
            let c = units[index]
            let next = index + 1 < units.count ? units[index + 1] : 0
            if let terminator = rawTerminator {
                if c == 10 {
                    if rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == terminator {
                        rawTerminator = nil
                    }
                    rawLine = ""
                } else { rawLine += String(decoding: [c], as: UTF16.self) }
            } else if blockComment {
                if c == 42 && next == 47 { blockComment = false; index += 1 }
            } else if statementComment {
                if c == 59 { statementComment = false; statement = "" }
            } else if let delimiter = quote {
                if c == delimiter {
                    if next == delimiter { index += 1 } else { quote = nil }
                }
            } else if c == 47 && next == 42 {
                blockComment = true; index += 1
            } else if (c == 42 && statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                        (c == 37 && next == 42) {
                statementComment = true
            } else if c == 39 || c == 34 {
                quote = c
                statement += "?"
            } else if c == 59 {
                let keyword = statement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["datalines", "cards", "lines", "datalines4", "cards4", "lines4"].contains(keyword) {
                    rawTerminator = keyword.hasSuffix("4") ? ";;;;" : ";"
                    rawLine = ""
                }
                statement = ""
            } else {
                statement += String(decoding: [c], as: UTF16.self)
            }
            index += 1
        }
        return quote == nil && !blockComment && !statementComment && rawTerminator == nil
    }
}
