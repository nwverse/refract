import Testing
@testable import RefractFrontend
import RefractIR

@Test func implicitIdentityIsRejectedInsteadOfUsingRowValue() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct SettingItem: Identifiable {
        let id: String
        let title: String
    }
    protocol TitlesModel: RefractModel {
        var items: [SettingItem] { get }
    }
    struct ImplicitIdentity: View {
        let model: TitlesModel
        var body: some View {
            List(model.items, id: \\.self) { item in
                Text(item.title)
            }
        }
    }
    """))
    print(unit.diagnostics.map(\.rendered))
    #expect(unit.diagnostics.contains { $0.code == "RFLIST002" })
}

@Test func identityRejectionKeepsModelDiagnostic() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol TitlesModel: RefractModel {
        var titles: [String] { get }
    }
    struct MissingIdentity: View {
        let model: TitlesModel
        var body: some View {
            List(model.titles) { title in
                Text(title)
            }
        }
    }
    """))
    print(unit.diagnostics.map(\.rendered))
    #expect(unit.diagnostics.contains { $0.code == "RFLIST001" })
    #expect(unit.diagnostics.contains { $0.code == "model.invalid_property" })
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_declaration" })
}
