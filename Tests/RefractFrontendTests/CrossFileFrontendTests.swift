import Foundation
import Testing
import RefractIR
import RefractArkUI
import RefractCompose
@testable import RefractFrontend

private let crossFileModel = SourceFile(path: "Model.swift", contents: """
protocol RowsModel: RefractModel {
    var rows: [RowItem] { get }
    func setEnabled(_ id: Int, value: Bool)
}
""")

private let crossFileItem = SourceFile(path: "RowItem.swift", contents: """
struct RowItem: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}
""")

private let crossFileChild = SourceFile(path: "ChildRow.swift", contents: """
struct ChildRow: View {
    let model: RowsModel
    let row: RowItem
    var body: some View { Text(row.title) }
}
""")

private let crossFileParent = SourceFile(path: "Parent.swift", contents: """
struct Parent: View {
    let model: RowsModel
    var body: some View {
        List(model.rows) { item in
            ChildRow(model: model, row: item)
        }
    }
}
""")

@Test func crossFileDeclarationsKeepPerFileNativeOutputs() throws {
    let units = Frontend.parse(sources: [crossFileParent, crossFileItem, crossFileChild, crossFileModel])
    #expect(units.allSatisfy { !$0.hasErrors }, Comment(rawValue: units.flatMap(\.diagnostics).map(\.rendered).joined(separator: "\n")))
    #expect(units.map(\.module.sourceFile) == ["Parent.swift", "RowItem.swift", "ChildRow.swift", "Model.swift"])
    #expect(units.allSatisfy { $0.module.models.count + $0.module.itemTypes.count <= 1 })
    let sources = NativeSourceSet(modules: units.map(\.module), models: units.flatMap(\.resolvedModels),
                                  itemTypes: units.flatMap(\.resolvedItemTypes))
    let parent = try #require(units.first { $0.module.sourceFile == "Parent.swift" })
    let child = try #require(units.first { $0.module.sourceFile == "ChildRow.swift" })
    let kotlin = try ComposeBackend().generate(module: parent.module, sources: sources)
    #expect(kotlin.contains("ChildRow(model = model, row = item)"))
    #expect(!kotlin.contains("interface RowsModel"))
    #expect(!kotlin.contains("data class RowItem"))
    let ark = try ArkUIBackend().generate(module: parent.module, sources: sources)
    #expect(ark.contains("import { ChildRow } from './ChildRow';"))
    #expect(ark.contains("import { RowsModel } from './Model';"))
    #expect(ark.contains("import { RowItem } from './RowItem';"))
    #expect(ark.contains("ChildRow({ model: this.model, row: item })"))
    let childArk = try ArkUIBackend().generate(module: child.module, sources: sources)
    #expect(childArk.contains("export struct ChildRow"))
    #expect(childArk.contains("import { RowsModel } from './Model';"))
    #expect(childArk.contains("import { RowItem } from './RowItem';"))
    let modelUnit = try #require(units.first { $0.module.sourceFile == "Model.swift" })
    let modelArk = try ArkUIBackend().generate(module: modelUnit.module, sources: sources)
    #expect(modelArk.contains("import { RowItem } from './RowItem';"))
    #expect(modelArk.contains("rows: BasicDataSource<RowItem>;"))
}

@Test func crossFileTypeResolutionIsIndependentOfInputOrderButRecursionStartsAtFirstInput() throws {
    let sources = [crossFileModel, crossFileItem, crossFileChild, crossFileParent]
    let first = Frontend.parse(sources: sources)
    let second = Frontend.parse(sources: Array(sources.reversed()))
    #expect(first.map(\.module.sourceFile) == Array(second.map(\.module.sourceFile).reversed()))
    for unit in first {
        let other = try #require(second.first { $0.module.sourceFile == unit.module.sourceFile })
        #expect(unit == other)
    }
}

@Test func crossFileRejectsDuplicateAndMissingDeclarations() {
    let duplicate = SourceFile(path: "Duplicate.swift", contents: """

    struct RowItem: Identifiable { let id: Int; let title: String; let enabled: Bool }
    """)

    let units = Frontend.parse(sources: [crossFileModel, crossFileItem, duplicate])
    let diagnostics = units.flatMap(\.diagnostics).filter { $0.code == "RFVIEW007" }
    #expect(diagnostics.count == 2)
    #expect(Set(diagnostics.map(\.location?.file)) == ["RowItem.swift", "Duplicate.swift"])
    #expect(diagnostics.map(\.location?.line) == [1, 2])

    let missing = Frontend.parse(sources: [crossFileModel, crossFileChild, crossFileParent])
    #expect(missing.flatMap(\.diagnostics).contains { $0.code == "RFLIST001" })
}

@Test func crossFileRejectsMismatchedChildInputs() {
    let parent = SourceFile(path: "Parent.swift", contents: """
    struct Parent: View {
        let model: RowsModel
        var body: some View { List(model.rows) { row in ChildRow(model: model, row: model) } }
    }
    """)
    let units = Frontend.parse(sources: [crossFileModel, crossFileItem, crossFileChild, parent])
    #expect(units.flatMap(\.diagnostics).contains { $0.code == "RFVIEW006" })
}

@Test func crossFileRejectsDirectAndIndirectRecursion() {
    let direct = Frontend.parse(sources: [
        SourceFile(path: "Parent.swift", contents: "struct Parent: View { var body: some View { Child() } }"),
        SourceFile(path: "Child.swift", contents: "struct Child: View { var body: some View { Child() } }"),
    ])
    #expect(direct.flatMap(\.diagnostics).contains { $0.code == "RFVIEW006" && $0.location?.file == "Child.swift" })

    let units = Frontend.parse(sources: [
        SourceFile(path: "Parent.swift", contents: "struct Parent: View { var body: some View { Child() } }"),
        SourceFile(path: "Child.swift", contents: "struct Child: View { var body: some View { Parent() } }"),
    ])
    let diagnostics = units.flatMap(\.diagnostics).filter { $0.code == "RFVIEW006" }
    #expect(diagnostics.count == 1)
    #expect(diagnostics[0].message.contains("Parent -> Child -> Parent"))
    let reversed = Frontend.parse(sources: [
        SourceFile(path: "Child.swift", contents: "struct Child: View { var body: some View { Parent() } }"),
        SourceFile(path: "Parent.swift", contents: "struct Parent: View { var body: some View { Child() } }"),
    ])
    #expect(reversed.flatMap(\.diagnostics).first { $0.code == "RFVIEW006" }?.message
        .contains("Child -> Parent -> Child") == true)
}

@Test func crossFileEnumSwitchUsesSharedCatalogWithoutDuplicateDeclaration() throws {
    let units = Frontend.parse(sources: [
        SourceFile(path: "Tab.swift", contents: "enum Tab { case home; case settings }"),
        SourceFile(path: "TabContent.swift", contents: """
        struct TabContent: View {
            let tab: Tab
            var body: some View {
                switch tab {
                case .home: Text(verbatim: "Home")
                case .settings: Text(verbatim: "Settings")
                }
            }
        }
        """),
    ])
    #expect(units.allSatisfy { !$0.hasErrors })
    #expect(units.map { $0.module.enums.count } == [1, 0])
    let sources = NativeSourceSet(modules: units.map(\.module))
    let kotlin = try ComposeBackend().generate(module: units[1].module, sources: sources)
    #expect(kotlin.contains("when (tab)"))
    #expect(kotlin.contains("Tab.home ->"))
    #expect(!kotlin.contains("enum class Tab"))
    let ark = try ArkUIBackend().generate(module: units[1].module, sources: sources)
    #expect(ark.contains("import { Tab } from './Tab';"))
    #expect(ark.contains("this.tab === Tab.home"))
    #expect(!ark.contains("export enum Tab"))
}

@Test func crossFileListsBindOwningProtocolAndDeduplicateCatalogs() throws {
    let model = SourceFile(path: "IntRowsModel.swift", contents: """
    protocol IntRowsModel: RefractModel { var rows: [IntRow] { get } }
    struct IntRow: Identifiable { let id: Int; let title: String }
    """)
    let other = SourceFile(path: "StringRowsModel.swift", contents: """
    protocol StringRowsModel: RefractModel { var rows: [StringRow] { get } }
    struct StringRow: Identifiable { let id: String; let title: String }
    """)
    let screens = SourceFile(path: "Screens.swift", contents: """
    struct IntRowsScreen: View {
        let model: IntRowsModel
        var body: some View { List(model.rows) { row in Text(row.title) } }
    }
    struct StringRowsScreen: View {
        let model: StringRowsModel
        var body: some View { List { ForEach(model.rows) { row in Text(row.title) } } }
    }
    """)
    let units = Frontend.parse(sources: [screens, other, model])
    #expect(units.allSatisfy { !$0.hasErrors })
    let owners = units[0].module.screens.map { screen -> String? in
        guard case let .list(children, _, _) = screen.body,
              case let .forEach(items, _) = children[0] else { return nil }
        return items.modelType
    }
    #expect(owners == ["IntRowsModel", "StringRowsModel"])
    let catalog = NativeSourceSet(modules: units.map(\.module), models: units.flatMap(\.resolvedModels),
                                  itemTypes: units.flatMap(\.resolvedItemTypes))
    #expect(catalog.models.map(\.name).sorted() == ["IntRowsModel", "StringRowsModel"])
    #expect(catalog.itemTypes.map(\.name).sorted() == ["IntRow", "StringRow"])
    let kotlin = try ComposeBackend().generate(module: units[0].module, sources: catalog)
    #expect(kotlin.contains("public fun IntRowsScreen(\n    model: IntRowsModel,"))
    #expect(kotlin.contains("public fun StringRowsScreen(\n    model: StringRowsModel,"))
    let ark = try ArkUIBackend().generate(module: units[0].module, sources: catalog)
    #expect(ark.contains("(row: IntRow)"))
    #expect(ark.contains("(row: StringRow)"))
}

@Test func arkCrossFileImportsRequireFlatExplicitSiblingPaths() throws {
    let module = Module(sourceFile: "Folder/Parent.swift", screens: [
        Screen(name: "Parent", body: .child(ChildView(name: "Child"), location: nil)),
    ])
    let dependency = Module(sourceFile: "Child.swift", screens: [
        Screen(name: "Child", body: .text(Expression(.verbatimText("Child")), modifiers: [], location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ArkUIBackend().generate(module: module, sources: NativeSourceSet(modules: [module, dependency]))
    }
}
