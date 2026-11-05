import AppKit
import PDFKit
import XCTest
@testable import SASCore

final class PDFListingTests: XCTestCase {
    private let listing = """
    Analysis of Variance
    Source\tDF\tSum of Squares\tMean Square\tF Value\tPr > F
    Model\t1\t1000.5952380952\t1000.5952380952\t309.3865030675\t0.0000021672
    Error\t6\t19.4047619048\t3.2341269841\t.\t.
    Corrected Total\t7\t1020.0000000000\t.\t.\t.

    Parameter Estimates
    Variable\tDF\tEstimate\tStandard Error\tt Value\tPr > |t|
    Intercept\t1\t2.2000000000\t0.9380831520\t2.3452078799\t0.080832
    predictor_with_a_long_name_for_the_regression_model\t1\t0.6000000000\t0.2828427125\t2.1213203436\t0.124027
    """

    @MainActor func testRegressionColumnsAlignAndRowsDoNotWrapInPDF() throws {
        try checkRegressionLayout(tables: [])
    }

    @MainActor func testRegressionColumnsAlignInMixedReportAppendix() throws {
        let table = ResultTable(procedure: "PRINT", title: "Printed observations",
                                headers: [ResultRow(cells: [ResultCell("x")])],
                                rows: [ResultRow(cells: [ResultCell("1")])])
        try checkRegressionLayout(tables: [table])
    }

    @MainActor private func checkRegressionLayout(tables: [ResultTable]) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = RunRequest(source: "\t/* café 🙂 */\n\tproc reg data=d;\n\tmodel y=x;\nrun;",
                                 sourceURL: nil, workingDirectory: directory)
        let result = RunResult(request: request, output: listing, diagnosticText: "NOTE: completed",
                               status: .success, exitCode: 0, tables: tables)
        let report = RunReport(result: result, appVersion: "test", runtimeVersion: "test")
        let destination = directory.appendingPathComponent("regression.pdf")
        try PDFReportRenderer.write(report, to: destination)
        let document = try XCTUnwrap(PDFDocument(url: destination))
        let page = try XCTUnwrap((0..<document.pageCount).compactMap { document.page(at: $0) }
            .first { ($0.string ?? "").contains("Analysis of Variance") })
        func bounds(_ token: String) throws -> NSRect {
            let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: token) + "(?!\\w)"
            let range = ((page.string ?? "") as NSString).range(of: pattern, options: .regularExpression)
            guard range.location != NSNotFound else {
                XCTFail("Missing \(token)")
                throw NSError(domain: "PDFListingTests", code: 1)
            }
            return try XCTUnwrap(page.selection(for: range)).bounds(for: page)
        }
        let model = try bounds("Model")
        let probability = try bounds("0.0000021672")
        XCTAssertEqual(model.midY, probability.midY, accuracy: 1, "The model p-value must stay on its row")
        let sumHeader = try bounds("Sum of Squares")
        XCTAssertEqual(sumHeader.minX, try bounds("1000.5952380952").minX, accuracy: 1)
        XCTAssertEqual(sumHeader.minX, try bounds("19.4047619048").minX, accuracy: 1)
        XCTAssertEqual(sumHeader.minX, try bounds("1020.0000000000").minX, accuracy: 1)
        let predictor = try bounds("predictor_with_a_long_name_for_the_regression_model")
        XCTAssertEqual(predictor.midY, try bounds("0.124027").midY, accuracy: 1)
        XCTAssertEqual(try bounds("Estimate").minX, try bounds("2.2000000000").minX, accuracy: 1)
        XCTAssertEqual(try bounds("Estimate").minX, try bounds("0.6000000000").minX, accuracy: 1)
        for token in ["0.0000021672", "0.124027", "Corrected Total"] {
            let rect = try bounds(token)
            XCTAssertGreaterThanOrEqual(rect.minX, 53)
            XCTAssertLessThanOrEqual(rect.maxX, page.bounds(for: .mediaBox).width - 53)
        }
        XCTAssertEqual(result.output, listing, "PDF presentation must not change captured stdout")
        XCTAssertTrue(report.text.contains(request.source))
        XCTAssertTrue(report.text.contains(listing))
    }
}
