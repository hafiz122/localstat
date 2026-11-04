import AppKit

@MainActor public final class TableDocumentView: NSView {
    private struct Fragment {
        let table: ResultTable
        let columns: [Int]
        let widths: [CGFloat]
        let rows: Range<Int>
        let contentRows: [ResultRow]
        let continuation: Int
    }

    private let paper = NSSize(width: 612, height: 792)
    private let margin: CGFloat = 40
    private let gap: CGFloat
    private let bodyFont = NSFont.systemFont(ofSize: 9.5)
    private let headerFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    private let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private var fragments: [Fragment] = []
    public let tables: [ResultTable]

    public init(tables: [ResultTable], forPrinting: Bool = false) {
        self.tables = tables
        gap = forPrinting ? 0 : 16
        super.init(frame: .zero)
        buildPages()
        frame = NSRect(origin: .zero, size: NSSize(width: paper.width, height: CGFloat(max(1, fragments.count)) * paper.height + CGFloat(max(0, fragments.count - 1)) * gap - (forPrinting ? 1 : 0)))
        setAccessibilityLabel("Formatted tables")
    }

    required init?(coder: NSCoder) { nil }
    public override var isFlipped: Bool { true }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    public override func accessibilityValue() -> Any? {
        tables.map { table in
            ([table.title, table.section] + table.headers.map { $0.cells.map(\.text).joined(separator: "\t") } +
             table.rows.map { $0.cells.map(\.text).joined(separator: "\t") } + table.notes)
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    public var pageCount: Int { fragments.count }

    public override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: fragments.count)
        return true
    }

    public override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * paper.height, width: paper.width, height: paper.height)
    }

    private func buildPages() {
        let available = paper.width - 2 * margin
        for table in tables {
            let count = table.columnCount
            guard count > 0 else { continue }
            let contentRows = table.rows + table.notes.map { ResultRow(kind: "note", cells: [ResultCell($0, span: count)]) }
            var base = Array(repeating: CGFloat(58), count: count)
            for row in [table.headers.last! ] + contentRows {
                var column = 0
                for cell in row.cells {
                    if cell.span == 1 && column < count {
                        let longest = cell.text.components(separatedBy: "\n").map(\.count).max() ?? 0
                        base[column] = max(base[column], min(175, CGFloat(longest) * 5.4 + 16))
                    }
                    column += cell.span
                }
            }
            base[0] = min(base[0], 165)
            var chunks: [[Int]] = []
            if base.reduce(0, +) <= available {
                chunks = [Array(0..<count)]
            } else if count == 1 {
                chunks = [[0]]
            } else {
                var next = 1
                while next < count {
                    var columns = [0]
                    var width = base[0]
                    repeat {
                        columns.append(next)
                        width += base[next]
                        next += 1
                    } while next < count && width + base[next] <= available
                    chunks.append(columns)
                }
            }
            for (chunkIndex, columns) in chunks.enumerated() {
                var widths = columns.map { min(base[$0], available) }
                let total = widths.reduce(0, +)
                if total > available {
                    let factor = available / total
                    widths = widths.map { max(24, floor($0 * factor)) }
                }
                var start = 0
                repeat {
                    let title = table.title + (chunkIndex > 0 ? " · columns continued" : "")
                    let titleHeight = textHeight(title, width: available, font: titleFont) + 8
                    let sectionHeight = table.section.isEmpty ? 0 : textHeight(table.section, width: available, font: bodyFont) + 6
                    let top = margin + titleHeight + sectionHeight
                    let headerHeight = table.headers.reduce(CGFloat(0)) { $0 + rowHeight($1, columns: columns, widths: widths, header: true) }
                    var used = top + headerHeight + 8
                    var end = start
                    while end < contentRows.count {
                        let height = rowHeight(contentRows[end], columns: columns, widths: widths, header: false)
                        if end > start && used + height > paper.height - margin { break }
                        used += min(height, paper.height - margin - top - headerHeight)
                        end += 1
                    }
                    fragments.append(Fragment(table: table, columns: columns, widths: widths, rows: start..<end, contentRows: contentRows, continuation: chunkIndex))
                    start = end
                } while start < contentRows.count
            }
        }
    }

    private func projected(_ row: ResultRow, columns: [Int]) -> [ResultCell] {
        var expanded: [(Range<Int>, ResultCell)] = []
        var start = 0
        for cell in row.cells {
            expanded.append((start..<(start + cell.span), cell))
            start += cell.span
        }
        var result: [ResultCell] = []
        var i = 0
        while i < columns.count {
            guard let entry = expanded.first(where: { $0.0.contains(columns[i]) }) else { i += 1; continue }
            var span = 1
            while i + span < columns.count && entry.0.contains(columns[i + span]) { span += 1 }
            result.append(ResultCell(entry.1.text, span: span))
            i += span
        }
        return result
    }

    private func rowHeight(_ row: ResultRow, columns: [Int], widths: [CGFloat], header: Bool) -> CGFloat {
        let cells = projected(row, columns: columns)
        var offset = 0
        var height: CGFloat = 25
        for cell in cells {
            let width = widths[offset..<min(offset + cell.span, widths.count)].reduce(0, +) - 12
            height = max(height, textHeight(cell.text, width: width, font: header ? headerFont : bodyFont) + 12)
            offset += cell.span
        }
        return min(height, 300)
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let rect = (text as NSString).boundingRect(with: NSSize(width: max(12, width), height: 10_000),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font, .paragraphStyle: paragraph])
        return ceil(rect.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let screen = NSGraphicsContext.current?.isDrawingToScreen ?? true
        for (index, fragment) in fragments.enumerated() {
            let originY = CGFloat(index) * (paper.height + gap)
            let page = NSRect(x: 0, y: originY, width: paper.width, height: paper.height)
            guard dirtyRect.intersects(page) else { continue }
            (screen ? NSColor.textBackgroundColor : .white).setFill()
            page.fill()
            if screen {
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: page.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
            draw(fragment, at: originY, screen: screen)
        }
    }

    private func draw(_ fragment: Fragment, at originY: CGFloat, screen: Bool) {
        let ink: NSColor = screen ? .labelColor : .black
        let muted: NSColor = screen ? .secondaryLabelColor : .darkGray
        var y = originY + margin
        let title = fragment.table.title + (fragment.continuation > 0 ? " · columns continued" : "")
        let available = paper.width - 2 * margin
        let titleHeight = textHeight(title, width: available, font: titleFont) + 8
        (title as NSString).draw(in: NSRect(x: margin, y: y, width: available, height: titleHeight - 8),
                                 withAttributes: [.font: titleFont, .foregroundColor: ink])
        y += titleHeight
        if !fragment.table.section.isEmpty {
            let sectionHeight = textHeight(fragment.table.section, width: available, font: bodyFont) + 6
            (fragment.table.section as NSString).draw(in: NSRect(x: margin, y: y, width: available, height: sectionHeight - 6),
                                                      withAttributes: [.font: bodyFont, .foregroundColor: muted])
            y += sectionHeight
        }
        for row in fragment.table.headers {
            let height = rowHeight(row, columns: fragment.columns, widths: fragment.widths, header: true)
            drawRow(row, columns: fragment.columns, widths: fragment.widths, y: y, height: height, header: true, screen: screen)
            y += height
        }
        for index in fragment.rows {
            let row = fragment.contentRows[index]
            let height = min(rowHeight(row, columns: fragment.columns, widths: fragment.widths, header: false), originY + paper.height - margin - y)
            drawRow(row, columns: fragment.columns, widths: fragment.widths, y: y, height: height, header: false, screen: screen)
            y += height
        }
    }

    private func drawRow(_ row: ResultRow, columns: [Int], widths: [CGFloat], y: CGFloat, height: CGFloat, header: Bool, screen: Bool) {
        let cells = projected(row, columns: columns)
        let background: NSColor = header || row.kind == "total" || row.kind == "section"
            ? (screen ? .controlBackgroundColor : NSColor(calibratedWhite: 0.92, alpha: 1))
            : (screen ? .textBackgroundColor : .white)
        let ink: NSColor = screen ? .labelColor : .black
        var x = margin
        var offset = 0
        for cell in cells {
            let width = widths[offset..<min(offset + cell.span, widths.count)].reduce(0, +)
            let rect = NSRect(x: x, y: y, width: width, height: height)
            background.setFill()
            rect.fill()
            (screen ? NSColor.separatorColor : NSColor.gray).setStroke()
            NSBezierPath(rect: rect).stroke()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byCharWrapping
            let font = header || row.kind != "data" ? headerFont : bodyFont
            (cell.text as NSString).draw(in: rect.insetBy(dx: 6, dy: 5), withAttributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            x += width
            offset += cell.span
        }
    }
}

public enum TablePrintRenderer {
    @MainActor public static func operation(for tables: [ResultTable], destination: URL? = nil) -> NSPrintOperation {
        let view = TableDocumentView(tables: tables, forPrinting: true)
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if let destination {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        }
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = "LocalStat Tables"
        operation.showsPrintPanel = destination == nil
        operation.showsProgressPanel = false
        return operation
    }
}
