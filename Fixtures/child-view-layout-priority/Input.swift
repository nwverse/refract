import SwiftUI

protocol ChildRowsModel: RefractModel {
    var rows: [ChildSettingItem] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct ChildSettingItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let enabled: Bool
}

struct ChildSettingRow: View {
    let settings: ChildRowsModel
    let row: ChildSettingItem

    var body: some View {
        HStack(alignment: .center) {
            VStack {
                Text(row.title)
                Text(row.subtitle)
            }.layoutPriority(1)
            refractView(
                ios: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in settings.setEnabled(row.id, value: value) }
                    )).accessibilityLabel(row.title).labelsHidden()
                },
                android: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in settings.setEnabled(row.id, value: value) }
                    )).refractNativeModifier(
                        .testTag("setting_toggle_\(row.id)"),
                        .contentDescription(row.title),
                        .retainCallback(identity: "settings.setEnabled")
                    ).labelsHidden()
                },
                harmonyOS: {
                    Toggle("settings.item\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in settings.setEnabled(row.id, value: value) }
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

struct ChildSettings: View {
    let model: ChildRowsModel

    var body: some View {
        List(model.rows) { row in
            ChildSettingRow(settings: model, row: row)
                .refractNativeModifier(.contentType("setting"))
        }
    }
}
