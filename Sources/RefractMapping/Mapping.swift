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
        try JSONDecoder().decode(Mapping.self, from: Data(contentsOf: url))
    }
}
