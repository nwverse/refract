import Foundation
import Testing
@testable import RefractMapping

@Suite("Published theme token schema")
struct ThemeTokenSchemaTests {
    @Test func onlyColorAcceptsAnInteractionObject() throws {
        let schema = try MappingJSONDocument(data: Data(Mapping.schemaJSON.utf8), file: "refract.schema.json")
        let definitions = try #require(schema.root.property("$defs"))
        for category in ["spacing", "radius", "font"] {
            let reference = try #require(definitions.property("tokens")?.property("properties")?
                .property(category)?.property("$ref")?.string)
            #expect(reference == "#/$defs/staticTokenValues")
        }
        let color = try #require(definitions.property("tokens")?.property("properties")?
            .property("color")?.property("$ref")?.string)
        #expect(color == "#/$defs/tokenValues")
        let interaction = try #require(definitions.property("interactionToken"))
        #expect(interaction.property("required")?.array?.map(\.string) == [
            "resolver", "normal", "disabled", "pressed", "focused",
        ])
    }
}
