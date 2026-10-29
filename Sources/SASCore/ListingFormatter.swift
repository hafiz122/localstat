import Foundation

public enum ListingFormatter {
    /// Pad contiguous tabular blocks for a monospace view. Raw stdout stays
    /// untouched in RunResult and exported logs.
    public static func aligned(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        while index < lines.count {
            guard lines[index].contains("\t") else {
                output.append(lines[index]); index += 1; continue
            }
            var rows: [[String]] = []
            while index < lines.count && lines[index].contains("\t") {
                rows.append(lines[index].components(separatedBy: "\t")); index += 1
            }
            let count = rows.map(\.count).max() ?? 0
            let widths = (0..<count).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
            output += rows.map { row in
                row.enumerated().map { column, cell in
                    column == row.count - 1 ? cell : cell + String(repeating: " ", count: widths[column] - cell.count + 2)
                }.joined()
            }
        }
        return output.joined(separator: "\n")
    }
}
