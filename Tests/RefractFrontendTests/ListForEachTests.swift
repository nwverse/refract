import Testing
@testable import RefractFrontend
import RefractIR

private func listSource(_ body: String, identityType: String = "String") -> SourceFile {
    SourceFile(path: "Input.swift", contents: """
    struct SettingItem: Identifiable {
        let id: \(identityType)
        let title: String
    }

    protocol SettingsListModel: RefractModel {
        var items: [SettingItem] { get }
    }

    struct IdentifiedList: View {
        let model: SettingsListModel

        var body: some View {
            \(body)
        }
    }
    """)
}

private func dynamicItems(_ unit: TranslationUnit) throws -> ListItems {
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let screen = try #require(unit.module.screens.first)
    guard case let .list(children, _, _) = screen.body, children.count == 1,
          case let .forEach(items, _) = children[0] else {
        Issue.record("Expected one dynamic ListItems child")
        throw TestError()
    }
    return items
}

private struct TestError: Error {}

@Test func forEachInsideListUsesTheCanonicalTypedListIR() throws {
    let canonical = Frontend.parse(listSource("""
    List(model.items) { item in
        Text(item.title)
    }
    """))
    let wrapped = Frontend.parse(listSource("""
    List {
        ForEach(model.items) { item in
            Text(item.title)
        }
    }
    """))
    let canonicalItems = try dynamicItems(canonical)
    let wrappedItems = try dynamicItems(wrapped)
    #expect(wrappedItems.collection.value == canonicalItems.collection.value)
    #expect(wrappedItems.itemName == "item")
    #expect(wrappedItems.itemType == "SettingItem")
    #expect(wrappedItems.key == "id")
    #expect(wrappedItems.keyType == .string)
    guard case let .text(wrappedText, wrappedModifiers, _) = wrappedItems.content,
          case let .text(canonicalText, _, _) = canonicalItems.content else {
        Issue.record("Expected typed text rows")
        return
    }
    #expect(wrappedText.value == canonicalText.value)
    #expect(wrappedModifiers.isEmpty)
}

@Test func explicitStoredIDAndIntegerIdentityReuseNativeListLowering() throws {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items, id: \\.id) { item in
            Text(item.title)
        }
    }
    """, identityType: "Int"))
    let items = try dynamicItems(unit)
    #expect(items.key == "id")
    #expect(items.keyType == .int)
}

@Test(arguments: ["\\.self", "\\.title", "\\.id.description", "\\SettingItem.id", "item.id"])
func forEachRejectsIdentityOtherThanTheDeclaredStoredID(identity: String) {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items, id: \(identity)) { item in
            Text(item.title)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST002"])
    #expect(unit.diagnostics[0].message.contains("stored id"))
}

@Test func misplacedForEachIsRejectedBeforeBackendLowering() {
    let unit = Frontend.parse(listSource("""
    VStack {
        ForEach(model.items) { item in
            Text(item.title)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST003"])
    #expect(unit.diagnostics[0].suggestion?.contains("List { ForEach(model.items)") == true)
}

@Test func nestedForEachCannotEscapeItsTypedRowScope() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items) { item in
            ForEach(model.items) { nested in
                Text(nested.title)
            }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST003"])
    #expect(unit.diagnostics[0].message.contains("sole dynamic child directly owned by List"))
}

@Test func eagerForEachHasNoIndexOrArrayFallback() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(0..<10) { index in
            Text(verbatim: "Row")
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST003"])
    #expect(unit.module.screens.isEmpty)
}

@Test func nestedCanonicalListCannotReuseTheOuterItemScope() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items) { item in
            List(model.items) { nested in
                Text(nested.title)
            }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST003"])
    #expect(unit.diagnostics[0].message.contains("cannot be nested"))
}

@Test func indexCollectionsAreNotIdentityFallbacks() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items.indices) { index in
            Text(verbatim: "Row")
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST002"])
    #expect(unit.diagnostics[0].message.contains("index"))
}

@Test func extraListTrailingClosuresAreDiagnosed() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items) { item in
            Text(item.title)
        }
    } content: {
        Text(verbatim: "Duplicate")
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFVIEW004"])
    #expect(unit.module.screens.isEmpty)
}

@Test func mixedStaticAndDynamicRowsAreRejectedInTheFrontend() {
    let unit = Frontend.parse(listSource("""
    List {
        Text(verbatim: "Header")
        ForEach(model.items) { item in
            Text(item.title)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFLIST003"])
    #expect(unit.diagnostics[0].message.contains("cannot be mixed"))
}

@Test func forEachPreservesUnknownItemPropertyDiagnostics() {
    let unit = Frontend.parse(listSource("""
    List {
        ForEach(model.items) { item in
            Text(item.missing)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFSEM001", "R.string.invalid_key"])
    #expect(unit.diagnostics[0].message.contains("no declared stored property `missing`"))
}
