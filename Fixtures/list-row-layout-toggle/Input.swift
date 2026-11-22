import SwiftUI

struct SettingRow: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

protocol SettingsModel: RefractModel {
    var rows: [SettingRow] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct ItemToggle: View {
    let model: SettingsModel

    var body: some View {
        List(model.rows) { row in
            VStack(spacing: 8) {
                Toggle("settings.item\(row.id)", isOn: Binding(
                    get: { row.enabled },
                    set: { value in model.setEnabled(row.id, value: value) }
                ))
            }
        }
    }
}
