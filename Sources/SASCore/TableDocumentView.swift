import AppKit

@MainActor public final class TableDocumentView: NSView {
    private static let numericPattern = try! NSRegularExpression(
        pattern: #"^(?:[+-]?\$?(?:(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?%?|\.)$"#)
    private struct Fragment {
        let table: ResultTable
        let columns: [Int]
        let widths: [CGFloat]
        let rows: Range<Int>
        let contentRows: [ResultRow]
        let continuation: Int
        let rowHeights: [CGFloat]
        let headerHeights: [CGFloat]
        let titleHeight: CGFloat
        let sectionHeight: CGFloat
    }

    private struct TextKey: Hashable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
    }

    typealias TextMeasurer = @MainActor (String, CGFloat, NSFont) -> CGFloat
    private let measureText: TextMeasurer
    private var textHeights: [TextKey: CGFloat] = [:]

    private let paper = NSSize(width: 612, height: 792)
    private let margin: CGFloat = 40
    private let gap: CGFloat
    private let bodyFont = NSFont.systemFont(ofSize: 9.5)
    private let headerFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    private let noteFont = NSFont.systemFont(ofSize: 9, weight: .regular)
    private let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private var fragments: [Fragment] = []
    public let tables: [ResultTable]
    private let forPrinting: Bool
    private var pageSize = NSSize.zero
    public private(set) var screenZoom: CGFloat = 1

    public convenience init(tables: [ResultTable], forPrinting: Bool = false) {
        self.init(tables: tables, forPrinting: forPrinting, measureText: Self.systemTextHeight)
    }

    init(tables: [ResultTable], forPrinting: Bool, measureText: @escaping TextMeasurer) {
        self.tables = tables
        self.forPrinting = forPrinting
        self.measureText = measureText
        gap = forPrinting ? 0 : 16
        super.init(frame: .zero)
        buildPages()
        // Fragments retain the layout; distinct cell strings need not stay in a cache.
        textHeights.removeAll(keepingCapacity: false)
        frame = NSRect(origin: .zero, size: NSSize(width: paper.width, height: CGFloat(max(1, fragments.count)) * paper.height + CGFloat(max(0, fragments.count - 1)) * gap - (forPrinting ? 1 : 0)))
        pageSize = frame.size
        setAccessibilityLabel("Formatted tables")
    }

    required init?(coder: NSCoder) { nil }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    public func setScreenZoom(_ zoom: CGFloat) {
        guard !forPrinting, zoom.isFinite else { return }
        screenZoom = min(max(zoom, 0.5), 2)
        frame.size = NSSize(width: pageSize.width * screenZoom, height: pageSize.height * screenZoom)
        bounds.size = pageSize
        needsDisplay = true
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    public override func accessibilityValue() -> Any? {
        let descriptions: [String] = tables.map { table in
            let headers: [String] = table.headers.map { row in
                row.cells.map(\.text).joined(separator: "\t")
            }
            let rows: [String] = table.rows.map { row in
                row.cells.map(\.text).joined(separator: "\t")
            }
            var lines: [String] = [table.title, table.section]
            lines.append(contentsOf: headers)
            lines.append(contentsOf: rows)
            lines.append(contentsOf: table.notes)
            return lines.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return descriptions.joined(separator: "\n\n")
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
                let title = table.title + (chunkIndex > 0 ? " · columns continued" : "")
                let titleHeight = textHeight(title, width: available, font: titleFont) + 8
                let sectionHeight = table.section.isEmpty ? 0 : textHeight(table.section, width: available, font: bodyFont) + 6
                let top = margin + titleHeight + sectionHeight
                let headerHeights = table.headers.map { rowHeight($0, columns: columns, widths: widths, header: true) }
                let headerHeight = headerHeights.reduce(CGFloat(0), +)
                let rowHeights = contentRows.map { rowHeight($0, columns: columns, widths: widths, header: false) }
                var start = 0
                repeat {
                    var used = top + headerHeight + 8
                    var end = start
                    while end < contentRows.count {
                        let height = rowHeights[end]
                        if end > start && used + height > paper.height - margin { break }
                        used += min(height, paper.height - margin - top - headerHeight)
                        end += 1
                    }
                    fragments.append(Fragment(table: table, columns: columns, widths: widths, rows: start..<end,
                                              contentRows: contentRows, continuation: chunkIndex, rowHeights: rowHeights,
                                              headerHeights: headerHeights, titleHeight: titleHeight, sectionHeight: sectionHeight))
                    start = end
                } while start < contentRows.count
            }
        }
    }

    private func projected(_ row: ResultRow, columns: [Int]) -> [ResultCell] {
        if columns.enumerated().allSatisfy({ $0.offset == $0.element }),
           row.cells.reduce(0, { $0 + $1.span }) == columns.count {
            return row.cells
        }
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
        var height: CGFloat = forPrinting ? 22 : 25
        for cell in cells {
            let padding: CGFloat = forPrinting ? 10 : 12
            let width = widths[offset..<min(offset + cell.span, widths.count)].reduce(0, +) - padding
            let font = row.kind == "note" ? noteFont : (header || row.kind != "data" ? headerFont : bodyFont)
            height = max(height, textHeight(cell.text, width: width, font: font) + padding)
            offset += cell.span
        }
        return min(height, 300)
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let key = TextKey(text: text, width: width, fontName: font.fontName, fontSize: font.pointSize)
        if let height = textHeights[key] { return height }
        let height = measureText(text, width, font)
        textHeights[key] = height
        return height
    }

    private static func systemTextHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
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
        let titleHeight = fragment.titleHeight
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: margin, y: y, width: available, height: titleHeight - 8),
                                 withAttributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: titleParagraph])
        y += titleHeight
        if !fragment.table.section.isEmpty {
            let sectionHeight = fragment.sectionHeight
            let sectionParagraph = NSMutableParagraphStyle()
            sectionParagraph.alignment = .center
            (fragment.table.section as NSString).draw(in: NSRect(x: margin, y: y, width: available, height: sectionHeight - 6),
                                                      withAttributes: [.font: bodyFont, .foregroundColor: muted, .paragraphStyle: sectionParagraph])
            y += sectionHeight
        }
        for (row, height) in zip(fragment.table.headers, fragment.headerHeights) {
            drawRow(row, columns: fragment.columns, widths: fragment.widths, y: y, height: height, header: true, screen: screen)
            y += height
        }
        for index in fragment.rows {
            let row = fragment.contentRows[index]
            let height = min(fragment.rowHeights[index], originY + paper.height - margin - y)
            drawRow(row, columns: fragment.columns, widths: fragment.widths, y: y, height: height, header: false, screen: screen)
            y += height
        }
    }

    private func drawRow(_ row: ResultRow, columns: [Int], widths: [CGFloat], y: CGFloat, height: CGFloat, header: Bool, screen: Bool) {
        let cells = projected(row, columns: columns)
        let ink: NSColor = screen ? .labelColor : .black
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let horizontalRule: NSColor = screen
            ? (isDark ? NSColor(calibratedRed: 0.37, green: 0.44, blue: 0.51, alpha: 1)
                      : NSColor(calibratedRed: 0.78, green: 0.84, blue: 0.89, alpha: 1))
            : NSColor(calibratedWhite: 0.64, alpha: 1)
        let headerFill: NSColor = screen
            ? (isDark ? NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.30, alpha: 1)
                      : NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.97, alpha: 1))
            : .white
        let summaryFill: NSColor = screen
            ? (isDark ? NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.25, alpha: 1)
                      : NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.98, alpha: 1))
            : .white
        let background: NSColor = header ? headerFill : (row.kind == "total" || row.kind == "section" ? summaryFill : (screen ? .textBackgroundColor : .white))
        let tableWidth = widths.reduce(0, +)
        let tableX = max(margin, (paper.width - tableWidth) / 2)
        background.setFill()
        NSRect(x: tableX, y: y, width: tableWidth, height: height).fill()
        if header || row.kind == "section" {
            horizontalRule.setStroke()
            let top = NSBezierPath()
            top.lineWidth = header && !screen ? 0.9 : 0.5
            top.move(to: NSPoint(x: tableX, y: y + 0.5))
            top.line(to: NSPoint(x: tableX + tableWidth, y: y + 0.5))
            top.stroke()
        }
        var x = tableX
        var offset = 0
        for cell in cells {
            let width = widths[offset..<min(offset + cell.span, widths.count)].reduce(0, +)
            let rect = NSRect(x: x, y: y, width: width, height: height)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byCharWrapping
            paragraph.alignment = header ? .center : (isNumeric(cell.text) ? .right : .left)
            let font = row.kind == "note" ? noteFont : (header || row.kind != "data" ? headerFont : bodyFont)
            let inset = forPrinting ? rect.insetBy(dx: 5, dy: 4) : rect.insetBy(dx: 6, dy: 5)
            (cell.text as NSString).draw(in: inset, withAttributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            x += width
            offset += cell.span
        }
        if row.kind != "note" {
            horizontalRule.setStroke()
            let bottom = NSBezierPath()
            bottom.lineWidth = header || row.kind == "total" || row.kind == "section" ? 0.8 : 0.35
            bottom.move(to: NSPoint(x: tableX, y: y + height - 0.5))
            bottom.line(to: NSPoint(x: tableX + tableWidth, y: y + height - 0.5))
            bottom.stroke()
        }
    }

    private func isNumeric(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return Self.numericPattern.firstMatch(in: trimmed, range: range) != nil
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
