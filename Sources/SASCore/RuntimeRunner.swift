import Foundation
import Darwin

public struct RunRequest {
    public let source: String
    public let sourceURL: URL?
    public let workingDirectory: URL

    public init(source: String, sourceURL: URL?, workingDirectory: URL) {
        self.source = source
        self.sourceURL = sourceURL
        self.workingDirectory = workingDirectory
    }
}

public enum RunStatus: Equatable {
    case success, programError, unsupported, cancelled
    case exited(Int32), crashed(Int32), launchFailure(String)

    public var description: String {
        switch self {
        case .success: return "Completed"
        case .programError: return "Program error (exit 1)"
        case .unsupported: return "Runtime gap or defect (exit 2)"
        case .cancelled: return "Cancelled"
        case .exited(let code): return "Exited with code \(code)"
        case .crashed(let signal): return "Runtime terminated by signal \(signal)"
        case .launchFailure(let reason): return "Could not run: \(reason)"
        }
    }
}

public struct Diagnostic: Equatable {
    public let message: String
    public let sourceLine: Int?
    public let expandedLine: Int?

    public static func parse(_ text: String) -> [Diagnostic] {
        let original = try! NSRegularExpression(pattern: #"\(L([0-9]+)\)"#)
        let expanded = try! NSRegularExpression(pattern: #"\(expanded L([0-9]+)\)"#)
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }.map {
            let line = String($0)
            func number(_ regex: NSRegularExpression) -> Int? {
                guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range(at: 1), in: line) else { return nil }
                return Int(line[range])
            }
            let expandedLine = number(expanded)
            return Diagnostic(message: line, sourceLine: expandedLine == nil ? number(original) : nil,
                              expandedLine: expandedLine)
        }
    }
}

public struct RunResult {
    public let request: RunRequest
    public let output: String
    public let diagnosticText: String
    public let status: RunStatus
    public let exitCode: Int32?
    public let tables: [ResultTable]
    public let tableIssue: String?
    public var diagnostics: [Diagnostic] { Diagnostic.parse(diagnosticText) }

    public init(request: RunRequest, output: String, diagnosticText: String, status: RunStatus, exitCode: Int32?, tables: [ResultTable] = [], tableIssue: String? = nil) {
        self.request = request
        self.output = output
        self.diagnosticText = diagnosticText
        self.status = status
        self.exitCode = exitCode
        self.tables = tables
        self.tableIssue = tableIssue
    }
}

@MainActor public protocol RuntimeRunner: AnyObject {
    var isRunning: Bool { get }
    func run(_ request: RunRequest) async -> RunResult
    func cancel()
}

@MainActor public final class LocalRuntimeRunner: RuntimeRunner {
    public private(set) var isRunning = false
    private let executable: URL
    private var process: Process?
    private var cancelled = false

    public init(executable: URL) { self.executable = executable }

    public func run(_ request: RunRequest) async -> RunResult {
        guard !isRunning else {
            return RunResult(request: request, output: "", diagnosticText: "A program is already running.",
                             status: .launchFailure("A program is already running."), exitCode: nil)
        }
        isRunning = true
        cancelled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("localstat-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            process = nil
            isRunning = false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let snapshot = directory.appendingPathComponent("program.sas")
            let tableFile = directory.appendingPathComponent("tables.json")
            try request.source.write(to: snapshot, atomically: true, encoding: .utf8)
            let child = Process()
            child.executableURL = executable
            child.arguments = [snapshot.path, "--tables-json", tableFile.path]
            child.currentDirectoryURL = request.workingDirectory
            let stdout = Pipe(), stderr = Pipe()
            child.standardOutput = stdout
            child.standardError = stderr
            child.standardInput = FileHandle.nullDevice
            process = child
            try child.run()

            // Both streams must drain concurrently: a full stderr pipe must never
            // prevent the child from completing while stdout is being read.
            async let outData = Self.drain(stdout.fileHandleForReading)
            async let errData = Self.drain(stderr.fileHandleForReading)
            let termination = await Self.wait(child)
            let output = String(decoding: await outData, as: UTF8.self)
            let errors = String(decoding: await errData, as: UTF8.self)
            let status: RunStatus
            if cancelled { status = .cancelled }
            else if termination.1 == .uncaughtSignal { status = .crashed(termination.0) }
            else {
                switch termination.0 {
                case 0: status = .success
                case 1: status = .programError
                case 2: status = .unsupported
                default: status = .exited(termination.0)
                }
            }
            let tables: [ResultTable]
            let tableIssue: String?
            do {
                let data = try Data(contentsOf: tableFile)
                tables = try JSONDecoder().decode(TableFile.self, from: data).validated()
                tableIssue = nil
            } catch {
                tables = []
                tableIssue = "Formatted tables are unavailable: \(error.localizedDescription)"
            }
            return RunResult(request: request, output: output, diagnosticText: errors,
                             status: status, exitCode: termination.0, tables: tables, tableIssue: tableIssue)
        } catch {
            return RunResult(request: request, output: "", diagnosticText: error.localizedDescription,
                             status: .launchFailure(error.localizedDescription), exitCode: nil)
        }
    }

    public func cancel() {
        guard let child = process, child.isRunning else { return }
        cancelled = true
        child.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    nonisolated private static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                try? handle.close()
                continuation.resume(returning: data)
            }
        }
    }

    nonisolated private static func wait(_ process: Process) async -> (Int32, Process.TerminationReason) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, process.terminationReason))
            }
        }
    }
}
