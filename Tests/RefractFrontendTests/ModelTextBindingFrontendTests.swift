import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendParsesExplicitModelTextBinding() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SearchResultsModel: RefractModel {
        var searchText: String { get }
        func setSearchText(_ value: String)
    }
    struct SearchScreen: View {
        let model: SearchResultsModel
        var body: some View {
            TextField("search.results.placeholder", text: Binding(
                get: { model.searchText },
                set: { value in model.setSearchText(value) }
            ))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .textInput(_, value, _, _) = unit.module.screens.first?.body,
          case let .valueProperty(.modelScalarBinding(binding)) = value.value else {
        Issue.record("Expected an explicit typed model text binding")
        return
    }
    #expect(binding == ModelScalarBinding(model: "model", property: "searchText", action: "setSearchText"))
    #expect(value.type == .string)
}

@Test(arguments: [
    "get: { model.searchText }, set: { value in value }",
    "get: { model.otherText }, set: { model.setSearchText($0) }",
    "get: { model.searchText }, set: { other.setSearchText($0) }",
    "get: { model.searchText }, set: { model.setSearchText(\"literal\") }",
    "get: { model.searchText }, set: { model.missing($0) }",
    "get: { model.searchText }, set: { value in model.setSearchText(value: value) }",
])
func frontendRejectsMismatchedModelTextBinding(_ binding: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SearchResultsModel: RefractModel {
        var searchText: String { get }
        var otherText: String { get }
        func setSearchText(_ value: String)
        func setOtherText(_ value: String)
    }
    struct SearchScreen: View {
        let model: SearchResultsModel
        let other: SearchResultsModel
        var body: some View {
            TextField("search.results.placeholder", text: Binding(\(binding)))
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsNonStringModelTextBinding() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol CounterModel: RefractModel {
        var count: Int { get }
        func setCount(_ value: Int)
    }
    struct SearchScreen: View {
        let model: CounterModel
        var body: some View {
            TextField("search.results.placeholder", text: Binding(
                get: { model.count }, set: { model.setCount($0) }
            ))
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsOptionalModelTextBinding() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SearchResultsModel: RefractModel {
        @refractText var searchText: String { get }
        func setSearchText(_ value: String)
    }
    struct SearchScreen: View {
        let model: SearchResultsModel
        var body: some View {
            TextField("search.results.placeholder", text: Binding(
                get: { model.searchText }, set: { model.setSearchText($0) }
            ))
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["state.invalid_projection"])
    #expect(unit.diagnostics[0].message == "`@refractText` model property `searchText` is nullable on native platforms and cannot provide an editable String binding.")
    #expect(unit.diagnostics[0].suggestion == "For an editable property, remove `@refractText` and retain its `setSearchText` action. Alternatively, move optional error or presence text to a separate read-only property")
    #expect(unit.diagnostics[0].location?.line == 8)
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsGetOnlyModelProjectionForTextInput() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SearchResultsModel: RefractModel {
        var searchText: String { get }
        func setSearchText(_ value: String)
    }
    struct SearchScreen: View {
        let model: SearchResultsModel
        var body: some View {
            TextField("search.results.placeholder", text: $model.searchText)
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}
