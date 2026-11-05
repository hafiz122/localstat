import AppKit
import Foundation
import PDFKit

public struct RunReport {
    public let result: RunResult
    public let generatedAt: Date
    public let appVersion: String
    public let runtimeVersion: String

    public init(result: RunResult, generatedAt: Date = Date(), appVersion: String, runtimeVersion: String) {
        self.result = result
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.runtimeVersion = runtimeVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var programName: String {
        result.request.sourceURL?.lastPathComponent ?? "Untitled.sas"
    }

    public var suggestedPDFName: String {
        let stem = (programName as NSString).deletingPathExtension
        return "\(stem)-report.pdf"
    }

    fileprivate var frontText: String {
        let generated = ISO8601DateFormatter().string(from: generatedAt)
        let sourceLocation = result.request.sourceURL?.path ?? "Unsaved editor buffer"
        let exitCode = result.exitCode.map(String.init) ?? "Not available"
        let source = result.request.source.isEmpty ? "(empty program)" : result.request.source
        return """
        LocalStat Run Report

        Program: \(programName)
        Source: \(sourceLocation)
        Working directory: \(result.request.workingDirectory.path)
        Generated: \(generated)
        Status: \(result.status.description)
        Exit code: \(exitCode)
        LocalStat: \(appVersion)
        Runtime: \(runtimeVersion)

        SOURCE PROGRAM
        \(source)
        """
    }

    fileprivate var outputText: String {
        result.output.isEmpty ? "No text output was produced." : result.output
    }

    fileprivate var diagnosticsText: String {
        result.diagnosticText.isEmpty ? "No diagnostics were produced." : result.diagnosticText
    }

    public var text: String {
        "\(frontText)\n\nOUTPUT\n\(outputText)\n\nDIAGNOSTICS\n\(diagnosticsText)"
    }
}

public enum PDFReportRenderer {
    @MainActor public static func write(_ report: RunReport, to destination: URL) throws {
        guard !report.result.tables.isEmpty else {
            let prefix = report.frontText + "\n\nOUTPUT\n"
            let range = NSRange(location: prefix.utf16.count, length: report.outputText.utf16.count)
            try writeText(report.text, programName: report.programName, listingRange: range, to: destination)
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("localstat-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let frontURL = folder.appendingPathComponent("front.pdf")
        let tablesURL = folder.appendingPathComponent("tables.pdf")
        let appendixURL = folder.appendingPathComponent("appendix.pdf")
        let front = report.frontText + "\n\nFORMATTED TABLES\n"
        let appendixPrefix = "RAW OUTPUT APPENDIX\n"
        let appendix = "\(appendixPrefix)\(report.outputText)\n\nDIAGNOSTICS\n\(report.diagnosticsText)\n"
        let appendixRange = NSRange(location: appendixPrefix.utf16.count, length: report.outputText.utf16.count)
        try writeText(front, programName: report.programName, to: frontURL)
        guard TablePrintRenderer.operation(for: report.result.tables, destination: tablesURL).run() else { throw PDFReportError.renderFailed }
        try writeText(appendix, programName: report.programName, listingRange: appendixRange, to: appendixURL)
        guard let combined = PDFDocument(url: frontURL), let tablePDF = PDFDocument(url: tablesURL),
              let appendixPDF = PDFDocument(url: appendixURL) else { throw PDFReportError.renderFailed }
        for document in [tablePDF, appendixPDF] {
            while document.pageCount > 0 {
                guard let page = document.page(at: 0) else { throw PDFReportError.renderFailed }
                document.removePage(at: 0)
                combined.insert(page, at: combined.pageCount)
            }
        }
        guard combined.write(to: destination) else { throw PDFReportError.renderFailed }
    }

    @MainActor private static func writeText(_ text: String, programName: String, listingRange: NSRange? = nil, to destination: URL) throws {
        _ = NSApplication.shared
        let printableWidth: CGFloat = 504
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: printableWidth, height: 720))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: printableWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: printableWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(attributedText(for: text, listingRange: listingRange, width: printableWidth))
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            textView.frame.size.height = max(1, ceil(layoutManager.usedRect(for: textContainer).height))
        }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792)
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.jobTitle = "LocalStat Run Report: \(programName)"
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw PDFReportError.renderFailed }
    }

    @MainActor private static func attributedText(for text: String, listingRange: NSRange?, width: CGFloat) -> NSAttributedString {
        let value = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        value.append(NSAttributedString(string: text, attributes: body))

        if let listingRange {
            let listing = (text as NSString).substring(with: listingRange) as NSString
            var search = NSRange(location: 0, length: listing.length)
            var blocks: [NSRange] = []
            while search.length > 0 {
                let block = listing.range(of: "(?m)^.*\\t.*(?:\\n.*\\t.*)*", options: .regularExpression, range: search)
                guard block.location != NSNotFound else { break }
                blocks.append(block)
                search = NSRange(location: NSMaxRange(block), length: listing.length - NSMaxRange(block))
            }
            for block in blocks.reversed() {
                let aligned = ListingFormatter.aligned(listing.substring(with: block))
                let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
                let widest = aligned.components(separatedBy: "\n").map {
                    ($0 as NSString).size(withAttributes: [.font: font]).width
                }.max() ?? 0
                let size = font.pointSize * min(1, (width - 1) / max(1, widest))
                var attributes = body
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                let range = NSRange(location: listingRange.location + block.location, length: block.length)
                value.replaceCharacters(in: range, with: NSAttributedString(string: aligned, attributes: attributes))
            }
        }

        let titleRange = (value.string as NSString).range(of: "LocalStat Run Report")
        value.addAttributes([
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.black
        ], range: titleRange)
        for heading in ["SOURCE PROGRAM", "OUTPUT", "FORMATTED TABLES", "RAW OUTPUT APPENDIX", "DIAGNOSTICS"] {
            let range = (value.string as NSString).range(of: heading)
            value.addAttributes([
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black
            ], range: range)
        }
        return value
    }
}

public enum PDFReportError: LocalizedError {
    case renderFailed

    public var errorDescription: String? {
        "LocalStat could not create the PDF report."
    }
}
