import Foundation

public struct ResultCell: Codable, Equatable {
    public let text: String
    public let span: Int

    public init(_ text: String, span: Int = 1) {
        self.text = text
        self.span = span
    }
}

public struct ResultRow: Codable, Equatable {
    public let kind: String
    public let cells: [ResultCell]

    public init(kind: String = "data", cells: [ResultCell]) {
        self.kind = kind
        self.cells = cells
    }
}

public struct ResultTable: Codable, Equatable {
    public let procedure: String
    public let title: String
    public let section: String
    public let headers: [ResultRow]
    public let rows: [ResultRow]
    public let notes: [String]

    public init(procedure: String, title: String, section: String = "", headers: [ResultRow], rows: [ResultRow], notes: [String] = []) {
        self.procedure = procedure
        self.title = title
        self.section = section
        self.headers = headers
        self.rows = rows
        self.notes = notes
    }

    public var columnCount: Int {
        var count = 0
        for cell in headers.last?.cells ?? [] {
            let (sum, overflow) = count.addingReportingOverflow(cell.span)
            if overflow { return 0 }
            count = sum
        }
        return count
    }
}

public struct TableFile: Codable {
    public let version: Int
    public let tables: [ResultTable]

    public func validated() throws -> [ResultTable] {
        guard version == 1 else { throw TableFileError.unsupportedVersion }
        for table in tables {
            let count = table.columnCount
            guard count > 0, count <= 100_000, !table.headers.isEmpty else { throw TableFileError.invalidShape }
            for row in table.headers + table.rows {
                var width = 0
                for cell in row.cells {
                    guard cell.span > 0, cell.span <= count - width else { throw TableFileError.invalidShape }
                    width += cell.span
                }
                guard width == count else { throw TableFileError.invalidShape }
            }
        }
        return tables
    }
}

public enum TableFileError: LocalizedError {
    case unsupportedVersion, invalidShape

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "The runtime produced an unsupported table format."
        case .invalidShape: return "The runtime produced an invalid table layout."
        }
    }
}
