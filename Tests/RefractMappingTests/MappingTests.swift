import Foundation
import Testing
@testable import RefractMapping

@Test func emptyMappingIsDeterministic() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("{\"schemaVersion\":1}".utf8).write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    #expect(try Mapping.load(contentsOf: temporary) == .empty)
}
