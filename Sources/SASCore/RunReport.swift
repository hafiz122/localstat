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

    public var text: String {
        let output = result.output.isEmpty ? "No text output was produced." : result.output
        let diagnostics = result.diagnosticText.isEmpty ? "No diagnostics were produced." : result.diagnosticText
        return "\(frontText)\n\nOUTPUT\n\(output)\n\nDIAGNOSTICS\n\(diagnostics)"
    }
}

public enum PDFReportRenderer {
    @MainActor public static func write(_ report: RunReport, to destination: URL) throws {
        guard !report.result.tables.isEmpty else {
            try writeText(report.text, programName: report.programName, to: destination)
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("localstat-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let frontURL = folder.appendingPathComponent("front.pdf")
        let tablesURL = folder.appendingPathComponent("tables.pdf")
        let appendixURL = folder.appendingPathComponent("appendix.pdf")
        let front = report.frontText + "\n\nFORMATTED TABLES\n"
        let raw = report.result.output.isEmpty ? "No text output was produced." : report.result.output
        let diagnostics = report.result.diagnosticText.isEmpty ? "No diagnostics were produced." : report.result.diagnosticText
        let appendix = "RAW OUTPUT APPENDIX\n\(raw)\n\nDIAGNOSTICS\n\(diagnostics)\n"
        try writeText(front, programName: report.programName, to: frontURL)
        guard TablePrintRenderer.operation(for: report.result.tables, destination: tablesURL).run() else { throw PDFReportError.renderFailed }
        try writeText(appendix, programName: report.programName, to: appendixURL)
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

    @MainActor private static func writeText(_ text: String, programName: String, to destination: URL) throws {
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
        textView.textStorage?.setAttributedString(attributedText(for: text))
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

    @MainActor private static func attributedText(for text: String) -> NSAttributedString {
        let value = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        value.append(NSAttributedString(string: text, attributes: body))

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
