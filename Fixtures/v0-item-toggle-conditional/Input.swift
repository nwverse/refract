import SwiftUI

protocol SettingsModel: RefractModel {
    var rows: [SettingRow] { get }
    var visible: Bool { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct SettingRow: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

struct ItemToggle: View {
    let model: SettingsModel

    var body: some View {
        List(model.rows) { row in
            if model.visible {
                Toggle("settings.item\(row.id)", isOn: Binding(
                    get: { row.enabled },
                    set: { value in model.setEnabled(row.id, value: value) }
                ))
            } else {
                Text("settings.item\(row.id)")
            }
        }
    }
}
