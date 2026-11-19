import SwiftUI

enum CatalogCategory {
    case all
    case book
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
            lhs.title < rhs.title || (lhs.title == rhs.title && lhs.id < rhs.id)
        }.refractProjection(name: "catalogItems")) { item in
            Text(item.title)
        }
    }
}
