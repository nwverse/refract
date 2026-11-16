import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct NestedForEach: View {
    let model: SettingsListModel

    var body: some View {
        List {
            ForEach(model.items) { item in
                ForEach(model.items) { nested in
                    Text(nested.title)
                }
            }
        }
    }
}
