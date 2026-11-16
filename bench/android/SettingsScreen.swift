import SwiftUI

protocol SettingsModel: RefractModel {
    var title: String { get }
    var rows: [SettingRow] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct SettingRow: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let enabled: Bool
}

struct SettingsScreen: View {
    let model: SettingsModel

    var body: some View {
        VStack {
            Text(model.title)
            List(model.rows) { row in
                HStack {
                    VStack {
                        Text(row.title)
                        Text(row.subtitle)
                    }
                    Toggle("Setting \(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { model.setEnabled(row.id, value: $0) }
                    ))
                }
            }
        }
    }
}
