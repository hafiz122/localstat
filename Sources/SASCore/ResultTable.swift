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

    public var columnCount: Int { headers.last?.cells.reduce(0) { $0 + $1.span } ?? 0 }
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
                guard row.cells.allSatisfy({ $0.span > 0 && $0.span <= count }),
                      row.cells.reduce(0, { $0 + $1.span }) == count else { throw TableFileError.invalidShape }
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
