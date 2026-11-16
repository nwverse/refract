import SwiftUI

struct Item {
    let label: String
}

struct ItemListView: View {
    var items: [Item]

    var body: some View {
        List(items) { item in
            Text(item.label)
        }
    }
}
