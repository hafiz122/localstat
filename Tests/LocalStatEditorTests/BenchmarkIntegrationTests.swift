import AppKit
import CryptoKit
import XCTest
@testable import LocalStat
import SASCore

final class BenchmarkIntegrationTests: XCTestCase {
    @MainActor func testPageCountsBelongToMeasuredVariant() {
        _ = NSApplication.shared
        let table = ResultTable(procedure: "PRINT", title: "Pages",
                                headers: [ResultRow(cells: [ResultCell("Value")])],
                                rows: (0..<100).map { ResultRow(cells: [ResultCell("\($0)")]) })
        let appView = TableDocumentView(tables: [table])
        let layoutView = TableDocumentView(tables: [table, table])
        XCTAssertGreaterThan(appView.pageCount, 0)
        XCTAssertNotEqual(appView.pageCount, layoutView.pageCount)
        XCTAssertEqual(pageCount(for: "runner", layoutView: nil, appDocumentView: appView), 0)
        XCTAssertEqual(pageCount(for: "app", layoutView: nil, appDocumentView: appView), appView.pageCount)
        XCTAssertEqual(pageCount(for: "layout", layoutView: layoutView, appDocumentView: appView), layoutView.pageCount)
        XCTAssertEqual(pageCount(for: "layout", layoutView: nil, appDocumentView: appView), 0)
    }

    @MainActor private func pageCount(for variant: String, layoutView: TableDocumentView?, appDocumentView: NSView?) -> Int {
        switch variant {
        case "layout": return layoutView?.pageCount ?? 0
        case "app": return (appDocumentView as? TableDocumentView)?.pageCount ?? 0
        default: return 0
        }
    }

    private enum MeasurementError: Error {
        case timedOut
    }

    @MainActor private func withDeadline(runner: LocalRuntimeRunner, timeoutNanoseconds: UInt64,
                                         operation: @escaping @MainActor () async -> RunResult) async throws -> RunResult {
        try Task.checkCancellation()
        let start = DispatchTime.now().uptimeNanoseconds
        var finished = false
        var timedOut = false
        let deadline = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                timedOut = true
                while !finished && !runner.isRunning {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                if !finished { runner.cancel() }
            } catch {}
        }
        defer {
            finished = true
            deadline.cancel()
        }
        let task = Task { await operation() }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in
                while !finished && !runner.isRunning {
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                if !finished { runner.cancel() }
            }
        }
        try Task.checkCancellation()
        if timedOut || DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
            throw MeasurementError.timedOut
        }
        return result
    }

    @MainActor private func run(_ request: RunRequest, using runner: LocalRuntimeRunner,
                                timeoutNanoseconds: UInt64 = 60_000_000_000) async throws -> RunResult {
        try await withDeadline(runner: runner, timeoutNanoseconds: timeoutNanoseconds) {
            await runner.run(request)
        }
    }

    @MainActor private func runApp(_ app: AppDelegate,
                                   timeoutNanoseconds: UInt64 = 60_000_000_000) async throws -> RunResult {
        try await withDeadline(runner: app.runner, timeoutNanoseconds: timeoutNanoseconds) {
            app.runProgram()
            while app.lastResult == nil {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return app.lastResult!
        }
    }

    private func sampleStatus(_ result: RunResult, expectedTables: Int) -> String {
        result.status == .success && result.tableIssue == nil && result.tables.count == expectedTables ? "ok" : "invalid"
    }

    private func fakeRuntime(_ body: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native benchmark \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("runtime")
        try ("#!/bin/sh\n" + body).write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return (directory, binary)
    }

    @MainActor func testNativeDeadlinesCancelAndReapRunnerAndAppProcesses() async throws {
        _ = NSApplication.shared
        for variant in ["runner", "app"] {
            let (directory, binary) = try fakeRuntime("echo $$ > pid\nexec /bin/sleep 10\n")
            let runner = LocalRuntimeRunner(executable: binary)
            let app = AppDelegate()
            let suite = "LocalStatBenchmark.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            app.appearanceDefaults = defaults
            app.runner = runner
            app.projectURL = directory
            app.buildWindow()
            app.addDocument(EditorDocument(url: nil, source: ""))
            defer {
                app.window.delegate = nil
                app.window.close()
                defaults.removePersistentDomain(forName: suite)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                if variant == "runner" {
                    _ = try await run(RunRequest(source: "", sourceURL: nil, workingDirectory: directory),
                                      using: runner, timeoutNanoseconds: 500_000_000)
                } else {
                    _ = try await runApp(app, timeoutNanoseconds: 500_000_000)
                }
                XCTFail("Expected \(variant) deadline to fail")
            } catch MeasurementError.timedOut {
            }
            XCTAssertLessThan(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9, 5, variant)
            XCTAssertFalse(runner.isRunning, variant)
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path) {
                let pid = try XCTUnwrap(Int32(String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
                XCTAssertEqual(kill(pid, 0), -1, "The \(variant) child must be gone before returning")
                XCTAssertEqual(errno, ESRCH)
            }
        }
    }

    @MainActor func testCancellingNativeMeasurementWaitsForChildExit() async throws {
        let (directory, binary) = try fakeRuntime("echo $$ > pid\nexec /bin/sleep 10\n")
        let runner = LocalRuntimeRunner(executable: binary)
        let task = Task {
            try await run(RunRequest(source: "", sourceURL: nil, workingDirectory: directory),
                          using: runner, timeoutNanoseconds: 10_000_000_000)
        }
        let startup = DispatchTime.now().uptimeNanoseconds
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path)
                && DispatchTime.now().uptimeNanoseconds - startup < 5_000_000_000 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let started = FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path)
        let start = DispatchTime.now().uptimeNanoseconds
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertLessThan(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9, 5)
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(started, "The fake runtime did not signal startup before cancellation")
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path) {
            let pid = try XCTUnwrap(Int32(String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
        }
    }

    @MainActor func testCompletedDeadlineDoesNotCancelTheNextRun() async throws {
        let (directory, binary) = try fakeRuntime("printf '{\"version\":1,\"tables\":[]}' > \"$3\"\nprintf 'CHECK 1\\n'\n")
        let runner = LocalRuntimeRunner(executable: binary)
        let request = RunRequest(source: "", sourceURL: nil, workingDirectory: directory)
        let first = try await run(request, using: runner, timeoutNanoseconds: 1_000_000_000)
        XCTAssertEqual(first.status, .success)
        XCTAssertNil(first.tableIssue)
        try "#!/bin/sh\nexec /bin/sleep 2\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let next = try await run(request, using: runner, timeoutNanoseconds: 5_000_000_000)
        XCTAssertEqual(next.status, .success)
        XCTAssertFalse(runner.isRunning)
    }

    func testNativeSampleStatusRequiresExpectedTableCount() {
        let request = RunRequest(source: "", sourceURL: nil, workingDirectory: URL(fileURLWithPath: "/tmp"))
        let empty = RunResult(request: request, output: "CHECK 1", diagnosticText: "", status: .success, exitCode: 0)
        XCTAssertEqual(sampleStatus(empty, expectedTables: 1), "invalid")
        XCTAssertEqual(sampleStatus(empty, expectedTables: 0), "ok")
        let failed = RunResult(request: request, output: "", diagnosticText: "", status: .programError, exitCode: 1)
        XCTAssertEqual(sampleStatus(failed, expectedTables: 0), "invalid")
        let malformed = RunResult(request: request, output: "", diagnosticText: "", status: .success, exitCode: 0, tableIssue: "Malformed")
        XCTAssertEqual(sampleStatus(malformed, expectedTables: 0), "invalid")
    }

    @MainActor func testMeasuredRuns() async throws {
        guard let configPath = ProcessInfo.processInfo.environment["LOCALSTAT_BENCHMARK_CONFIG"] else {
            throw XCTSkip("Opt-in measurement: set LOCALSTAT_BENCHMARK_CONFIG")
        }
        let configURL = URL(fileURLWithPath: configPath)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let binary = URL(fileURLWithPath: try XCTUnwrap(config["binary"] as? String))
        let work = URL(fileURLWithPath: try XCTUnwrap(config["work"] as? String))
        let output = URL(fileURLWithPath: try XCTUnwrap(config["output"] as? String))
        guard !FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("Do not overwrite an experiment")
            return
        }
        let cases = try XCTUnwrap(config["cases"] as? [[String: Any]])
        let warmups = try XCTUnwrap(config["warmups"] as? Int)
        let repetitions = try XCTUnwrap(config["repetitions"] as? Int)
        let measureLayout = config["measure_layout"] as? Bool ?? false
        _ = NSApplication.shared
        let oldAppearance = NSApp.appearance
        defer { NSApp.appearance = oldAppearance }
        var samples: [[String: Any]] = []
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let rows = try XCTUnwrap(item["rows"] as? Int)
            let folder = work.appendingPathComponent(try XCTUnwrap(item["directory"] as? String))
            let source = try String(contentsOf: folder.appendingPathComponent(try XCTUnwrap(item["source"] as? String)), encoding: .utf8)
            let suite = "LocalStatBenchmark.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let app = AppDelegate()
            app.appearanceDefaults = defaults
            app.projectURL = folder
            let runner = LocalRuntimeRunner(executable: binary)
            app.runner = runner
            app.buildWindow()
            app.window.appearance = NSAppearance(named: .aqua)
            app.window.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 780), display: true)
            app.addDocument(EditorDocument(url: nil, source: source))
            app.window.orderFront(nil)
            defer {
                app.window.delegate = nil
                app.window.close()
                defaults.removePersistentDomain(forName: suite)
            }
            let reference = measureLayout && ["freq", "print"].contains(name)
                ? try await run(RunRequest(source: source, sourceURL: nil, workingDirectory: folder), using: runner) : nil
            for iteration in 0..<(1 + warmups + repetitions) {
                let phase = iteration == 0 ? "first" : (iteration <= warmups ? "warmup" : "measured")
                let variants = reference == nil ? ["runner", "app"] : ["runner", "app", "layout"]
                for variant in (iteration % 2 == 0 ? variants : Array(variants.reversed())) {
                let start = DispatchTime.now().uptimeNanoseconds
                let result: RunResult
                var layoutView: TableDocumentView?
                if variant == "layout", let reference {
                    result = reference
                    layoutView = TableDocumentView(tables: reference.tables)
                } else if variant == "runner" {
                    result = try await run(RunRequest(source: source, sourceURL: nil, workingDirectory: folder), using: runner)
                } else {
                    result = try await runApp(app)
                    app.window.contentView?.layoutSubtreeIfNeeded()
                    app.window.displayIfNeeded()
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                let pageCount = pageCount(for: variant, layoutView: layoutView, appDocumentView: app.tableScroll.documentView)
                XCTAssertEqual(result.status, .success)
                XCTAssertNil(result.tableIssue)
                let expectedTables = ["freq", "print"].contains(name) ? 1 : 0
                XCTAssertEqual(result.tables.count, expectedTables)
                let hash = SHA256.hash(data: Data(result.output.utf8)).map { String(format: "%02x", $0) }.joined()
                samples.append(["workload": name, "rows": rows, "phase": phase, "iteration": iteration,
                                "status": sampleStatus(result, expectedTables: expectedTables),
                                "wall_s": elapsed, "variant": variant,
                                "stdout_sha256": hash, "table_count": result.tables.count,
                                "page_count": pageCount,
                                "table_rows": result.tables.reduce(0) { $0 + $1.rows.count }])
                try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
                }
            }
        }
    }
}
