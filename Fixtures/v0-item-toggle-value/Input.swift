import SwiftUI

protocol SettingsModel: RefractModel {
    var rows: [SettingRow] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct SettingRow: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

struct ValueItemToggle: View {
    let model: SettingsModel

    var body: some View {
        List(model.rows) { value in
            Toggle("settings.item\(value.id)", isOn: Binding(
                get: { value.enabled },
                set: { value in model.setEnabled(value.id, value: value) }
            ))
        }
    }
}
