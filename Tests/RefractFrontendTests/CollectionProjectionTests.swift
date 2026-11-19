import Testing
@testable import RefractFrontend
import RefractIR

private let projectionSource = """
enum CatalogCategory {
    case all
    case book
    case movie
}
struct CatalogItem: Identifiable {
    let id: Int
    let title: String
    let category: CatalogCategory
    let rank: Int
}
protocol CatalogModel: RefractModel {
    var items: [CatalogItem] { get }
}
struct CatalogScreen: View {
    let model: CatalogModel
    let category: CatalogCategory
    var body: some View {
        List(model.items.filter { item in
            category == .all || item.category == category
        }.sorted { lhs, rhs in
            lhs.rank < rhs.rank || (lhs.rank == rhs.rank && lhs.id < rhs.id)
        }.refractProjection(name: "catalogItems")) { item in
            Text(item.title)
        }
    }
}
"""

@Test func frontendParsesTypedCollectionProjection() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: projectionSource))
    #expect(unit.diagnostics.isEmpty)
    guard case let .list(children, _, _) = unit.module.screens.first?.body,
          case let .forEach(items, _) = children.first else {
        Issue.record("Expected a projected dynamic list")
        return
    }
    #expect(items.projection == CollectionProjection(name: "catalogItems", categoryProperty: "category",
        categoryEnum: "CatalogCategory", categoryParameter: "category", sortProperty: "rank", ascending: true))
}

@Test(arguments: [("<", true), (">", false)])
func frontendMapsSortDirectionAndTieBreak(_ direction: String, _ ascending: Bool) {
    let source = projectionSource
        .replacingOccurrences(of: "lhs.rank < rhs.rank", with: "lhs.rank \(direction) rhs.rank")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.isEmpty)
    guard case let .list(children, _, _) = unit.module.screens.first?.body,
          case let .forEach(items, _) = children.first else {
        Issue.record("Expected a projected dynamic list")
        return
    }
    #expect(items.projection?.ascending == ascending)
    #expect(items.projection?.sortProperty == "rank")
}

@Test func frontendAcceptsCategoryAllResetForMatchingInput() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: projectionSource))
    #expect(unit.diagnostics.isEmpty)
    guard case let .list(children, _, _) = unit.module.screens.first?.body,
          case let .forEach(items, _) = children.first else {
        Issue.record("Expected the category reset projection")
        return
    }
    #expect(items.projection?.categoryParameter == "category")
    #expect(items.projection?.categoryEnum == "CatalogCategory")
}

@Test func frontendRejectsDescendingIdTieBreak() {
    let source = projectionSource.replacingOccurrences(of: "lhs.id < rhs.id", with: "lhs.id > rhs.id")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.contains { $0.code == "RFLIST004" })
}

@Test func frontendRejectsResetUsingDifferentCategoryInput() {
    let source = projectionSource
        .replacingOccurrences(of: "let category: CatalogCategory", with: "let category: CatalogCategory\n    let other: CatalogCategory")
        .replacingOccurrences(of: "category == .all", with: "other == .all")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.contains { $0.code == "RFLIST004" })
}
@Test(arguments: [
    ("item.title == \"book\"", "lhs.rank < rhs.rank || (lhs.rank == rhs.rank && lhs.id < rhs.id)"),
    ("category == .all || item.category == category", "lhs.rank < rhs.rank"),
    ("category == .all || item.category == category", "lhs.title < rhs.title || (lhs.title == rhs.title && lhs.id < rhs.id)"),
])
func frontendRejectsUnsupportedProjectionClosures(_ filter: String, _ sort: String) {
    let input = projectionSource
        .replacingOccurrences(of: "category == .all || item.category == category", with: filter)
        .replacingOccurrences(of: "lhs.rank < rhs.rank || (lhs.rank == rhs.rank && lhs.id < rhs.id)", with: sort)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.contains { $0.code == "RFLIST004" })
}
