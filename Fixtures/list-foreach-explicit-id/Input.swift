import SwiftUI

struct ExplicitIDItem: Identifiable {
    let id: Int
    let title: String
}

protocol ExplicitIDListModel: RefractModel {
    var items: [ExplicitIDItem] { get }
}

struct ExplicitIDList: View {
    let model: ExplicitIDListModel

    var body: some View {
        List {
            ForEach(model.items, id: \.id) { item in
                Text(item.title)
            }
        }
    }
}
