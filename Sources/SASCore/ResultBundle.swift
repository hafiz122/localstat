import Foundation

public struct ResultGraphic {
    public let name: String
    public let procedure: String
    public let svg: Data

    public init(name: String, procedure: String, svg: Data) {
        self.name = name
        self.procedure = procedure
        self.svg = svg
    }
}

struct ResultBundle {
    let tables: [ResultTable]
    let graphics: [ResultGraphic]

    private static let maximumGraphicCount = 32
    private static let maximumGraphicBytes = 8 * 1024 * 1024
    private static let maximumTotalGraphicBytes = 32 * 1024 * 1024

    private struct Manifest: Decodable {
        let schema_version: Int
        let complete: Bool
        let exit_code: Int32
        let status: String
        let objects: [Object]
    }

    private struct Object: Decodable {
        let kind: String
        let path: String
        let name: String?
        let procedure: String?
        let index: Int?
    }

    static func load(from directory: URL, exitCode: Int32) throws -> ResultBundle {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schema_version == 1 else { throw BundleError.unsupportedVersion }
        guard manifest.complete else { throw BundleError.incomplete }
        guard manifest.exit_code == exitCode, manifest.status == statusName(for: exitCode) else {
            throw BundleError.exitMismatch
        }

        let listing = manifest.objects.filter { $0.kind == "listing" }
        let diagnostics = manifest.objects.filter { $0.kind == "diagnostics" }
        let tableObjects = manifest.objects.filter { $0.kind == "table" }
        let graphicObjects = manifest.objects.filter { $0.kind == "graphic" }
        guard listing.count == 1, listing[0].path == "listing.txt",
              diagnostics.count == 1, diagnostics[0].path == "diagnostics.txt",
              graphicObjects.count <= maximumGraphicCount,
              manifest.objects.count == listing.count + diagnostics.count + tableObjects.count + graphicObjects.count else {
            throw BundleError.invalidObjects
        }
        for name in ["listing.txt", "diagnostics.txt", "tables.json"] {
            let path = directory.appendingPathComponent(name).path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw BundleError.missingArtifact(name)
            }
        }

        let tableData = try Data(contentsOf: directory.appendingPathComponent("tables.json"))
        let tables = try JSONDecoder().decode(TableFile.self, from: tableData).validated()
        guard tableObjects.count == tables.count else { throw BundleError.invalidObjects }
        var indices = Set<Int>()
        for object in tableObjects {
            guard object.path == "tables.json", let index = object.index,
                  tables.indices.contains(index), indices.insert(index).inserted,
                  object.procedure == tables[index].procedure,
                  object.name == tables[index].title else {
                throw BundleError.invalidObjects
            }
        }
        var graphics = [ResultGraphic?](repeating: nil, count: graphicObjects.count)
        var totalBytes = 0
        for object in graphicObjects {
            guard let index = object.index, graphics.indices.contains(index), graphics[index] == nil,
                  object.path == String(format: "graphics/plot-%04d.svg", index + 1),
                  let name = object.name, !name.isEmpty,
                  let procedure = object.procedure, !procedure.isEmpty else {
                throw BundleError.invalidObjects
            }
            let file = directory.appendingPathComponent(object.path)
            let resolvedRoot = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRoot),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  size <= maximumGraphicBytes,
                  totalBytes <= maximumTotalGraphicBytes - size else {
                throw BundleError.invalidObjects
            }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: maximumGraphicBytes + 1) ?? Data()
            guard bytes.count == size, String(data: bytes, encoding: .utf8) != nil else {
                throw BundleError.invalidObjects
            }
            totalBytes += bytes.count
            graphics[index] = ResultGraphic(name: name, procedure: procedure, svg: bytes)
        }
        guard graphics.allSatisfy({ $0 != nil }) else { throw BundleError.invalidObjects }
        return ResultBundle(tables: tables, graphics: graphics.compactMap { $0 })
    }

    private static func statusName(for exitCode: Int32) -> String {
        switch exitCode {
        case 0: "success"
        case 1: "program_error"
        case 2: "unsupported"
        default: "exited"
        }
    }
}

enum BundleError: LocalizedError {
    case unsupportedVersion, incomplete, exitMismatch, invalidObjects, missingArtifact(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "The runtime produced an unsupported result bundle version."
        case .incomplete: "The runtime did not finish writing its result bundle."
        case .exitMismatch: "The result bundle does not match the runtime exit status."
        case .invalidObjects: "The result bundle contains invalid or unrecognized objects."
        case .missingArtifact(let name): "The result bundle is missing \(name)."
        }
    }
}
