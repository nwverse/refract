import Foundation
import RefractIR

/// The empty mapping is the initial contract; declared mappings grow in their own files.
public struct Mapping: Codable, Equatable, Sendable {
    public let schemaVersion: Int

    public init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
    }

    public static let empty = Mapping()

    public static func load(contentsOf url: URL) throws -> Mapping {
        try load(data: Data(contentsOf: url), file: url.lastPathComponent)
    }

    public static func load(data: Data, file: String) throws -> Mapping {
        do {
            let mapping = try JSONDecoder().decode(Mapping.self, from: data)
            guard mapping.schemaVersion == 1 else {
                throw Diagnostic(code: "mapping.unsupported_version",
                                 message: "Mapping schema version \(mapping.schemaVersion) is not supported.",
                                 suggestion: "Use mapping schema version 1.", location: SourceLocation(file: file, line: 1, column: 1))
            }
            return mapping
        } catch let diagnostic as Diagnostic { throw diagnostic }
        catch {
            throw Diagnostic(code: "mapping.invalid_json", message: "The mapping cannot be decoded: \(error).",
                             suggestion: "Provide a valid versioned refract.json.",
                             location: SourceLocation(file: file, line: 1, column: 1))
        }
    }
}
