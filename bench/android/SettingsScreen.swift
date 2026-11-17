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
            Text(model.title).font(DesignTypography.screenTitle).padding(16)
            List(model.rows) { row in
                GeneratedSettingRow(model: model, row: row)
                    .refractNativeModifier(.contentType("setting"))
            }
            .refractNativeModifier(.testTag("settings_list"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GeneratedSettingRow: View {
    let model: SettingsModel
    let row: SettingRow

    var body: some View {
        HStack(alignment: .center) {
            VStack {
                Text(row.title).font(DesignTypography.rowTitle)
                Text(row.subtitle).font(DesignTypography.rowSubtitle)
            }.layoutPriority(1)
            refractView(
                ios: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in model.setEnabled(row.id, value: value) }
                    )).accessibilityLabel(row.title).labelsHidden()
                },
                android: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in model.setEnabled(row.id, value: value) }
                    )).refractNativeModifier(
                        .testTag("setting_toggle_\(row.id)"),
                        .contentDescription(row.title),
                        .retainCallback(identity: "settings.setEnabled")
                    ).labelsHidden()
                },
                harmonyOS: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in model.setEnabled(row.id, value: value) }
                    ))
                    .accessibilityLabel(row.title)
                    .refractNativeModifier(.testTag("setting_toggle_\(row.id)")).labelsHidden()
                }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(horizontal: 16, vertical: 8)
        .refractNativeModifier(.testTag("setting_row_\(row.id)"))
    }
}
