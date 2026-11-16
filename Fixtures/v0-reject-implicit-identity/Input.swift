import SwiftUI

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
        List(model.items, id: \.self) { item in
            Text(item.title)
        }
    }
}
