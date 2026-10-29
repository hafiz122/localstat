import AppKit
import Foundation

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

    public var text: String {
        let generated = ISO8601DateFormatter().string(from: generatedAt)
        let sourceLocation = result.request.sourceURL?.path ?? "Unsaved editor buffer"
        let exitCode = result.exitCode.map(String.init) ?? "Not available"
        let source = result.request.source.isEmpty ? "(empty program)" : result.request.source
        let output = result.output.isEmpty ? "No text output was produced." : result.output
        let diagnostics = result.diagnosticText.isEmpty ? "No diagnostics were produced." : result.diagnosticText
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

        OUTPUT
        \(output)

        DIAGNOSTICS
        \(diagnostics)
        """
    }
}

public enum PDFReportRenderer {
    @MainActor public static func write(_ report: RunReport, to destination: URL) throws {
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
        textView.textStorage?.setAttributedString(attributedText(for: report))
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            textView.frame.size.height = max(720, ceil(layoutManager.usedRect(for: textContainer).height))
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
        operation.jobTitle = "LocalStat Run Report: \(report.programName)"
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw PDFReportError.renderFailed }
    }

    @MainActor private static func attributedText(for report: RunReport) -> NSAttributedString {
        let value = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        value.append(NSAttributedString(string: report.text, attributes: body))

        let titleRange = (value.string as NSString).range(of: "LocalStat Run Report")
        value.addAttributes([
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.black
        ], range: titleRange)
        for heading in ["SOURCE PROGRAM", "OUTPUT", "DIAGNOSTICS"] {
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
