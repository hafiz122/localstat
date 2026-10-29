import XCTest
@testable import SASCore

final class RuntimeRunnerTests: XCTestCase {
    func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sas runner spaces \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func executable(_ body: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("test runtime")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    func testDiagnosticCoordinates() {
        let lines = Diagnostic.parse("ERROR(L3): bad token\nERROR(expanded L9): macro\nNOTE: finished\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].sourceLine, 3)
        XCTAssertNil(lines[1].sourceLine)
        XCTAssertEqual(lines[1].expandedLine, 9)
        XCTAssertNil(lines[2].sourceLine)
    }
    func testReadableListingKeepsTableColumnsAligned() {
        let raw = "Heading\nName\tValue\nx\t12\nlong\t3\n\nTail\n"
        XCTAssertEqual(ListingFormatter.aligned(raw), "Heading\nName  Value\nx     12\nlong  3\n\nTail\n")
    }
    @MainActor func testSnapshotsPathsAndLargeConcurrentStreams() async throws {
        let directory = try workspace()
        let script = try executable("""
        cat "$1"
        pwd
        i=0
        while [ "$i" -lt 5000 ]; do
          printf 'out-1234567890123456789012345678901234567890\\n'
          printf 'err-1234567890123456789012345678901234567890\\n' >&2
          i=$((i + 1))
        done
        """, in: directory)
        let runner = LocalRuntimeRunner(executable: script)
        let request = RunRequest(source: "unsaved editor contents\n", sourceURL: directory.appendingPathComponent("not on disk.sas"), workingDirectory: directory)
        let result = await runner.run(request)
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.hasPrefix("unsaved editor contents\n"))
        XCTAssertTrue(result.output.contains(directory.path))
        XCTAssertEqual(result.output.components(separatedBy: "out-").count - 1, 5000)
        XCTAssertEqual(result.diagnosticText.components(separatedBy: "err-").count - 1, 5000)
        XCTAssertFalse(runner.isRunning)
    }
    @MainActor func testFailureClassificationAndRecovery() async throws {
        let directory = try workspace()
        let absent = LocalRuntimeRunner(executable: directory.appendingPathComponent("absent"))
        let request = RunRequest(source: "", sourceURL: nil, workingDirectory: directory)
        let failed = await absent.run(request)
        guard case .launchFailure = failed.status else { return XCTFail("Expected launch failure") }
        XCTAssertFalse(absent.isRunning)
        for (code, status) in [(0, RunStatus.success), (1, .programError), (2, .unsupported), (7, .exited(7))] {
            let script = try executable("exit \(code)\n", in: directory)
            let result = await LocalRuntimeRunner(executable: script).run(request)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.exitCode, Int32(code))
        }
        let crash = try executable("kill -KILL $$\n", in: directory)
        let crashed = await LocalRuntimeRunner(executable: crash).run(request)
        XCTAssertEqual(crashed.status, .crashed(9))
    }
    @MainActor func testCancellationEscalationAndSingleRun() async throws {
        let directory = try workspace()
        let script = try executable("trap '' TERM\nprintf ready > ready\nwhile :; do :; done\n", in: directory)
        let runner = LocalRuntimeRunner(executable: script)
        let request = RunRequest(source: "", sourceURL: nil, workingDirectory: directory)
        let task = Task { await runner.run(request) }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path))
        XCTAssertTrue(runner.isRunning)
        let overlap = await runner.run(request)
        guard case .launchFailure = overlap.status else { return XCTFail("Overlapping run accepted") }
        let started = Date()
        runner.cancel()
        let result = await task.value
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.exitCode, 9)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 1.9)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(runner.isRunning)
    }
    @MainActor func testBundledRuntimeFreshStateAndRelativeIncludes() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = root.appendingPathComponent("dist/LocalStat.app/Contents/Helpers/opensas")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Run scripts/build.sh first for packaged-runtime integration") }
        let directory = try workspace()
        try "data work.local; x=42; run;".write(to: directory.appendingPathComponent("input file.sas"), atomically: true, encoding: .utf8)
        let runner = LocalRuntimeRunner(executable: binary)
        let result = await runner.run(RunRequest(source: "%include 'input file.sas'; proc print data=work.local; run;", sourceURL: nil, workingDirectory: directory))
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.output.contains("42"))
        let next = await runner.run(RunRequest(source: "proc print data=work.local; run;", sourceURL: nil, workingDirectory: directory))
        XCTAssertEqual(next.status, .programError)
        XCTAssertTrue(next.diagnosticText.contains("PROC PRINT with no dataset"), next.diagnosticText)
    }
}
