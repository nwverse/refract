import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct UnknownForEachProperty: View {
    let model: SettingsListModel

    var body: some View {
        List {
            ForEach(model.items) { item in
                Text(item.missing)
            }
        }
    }
}
