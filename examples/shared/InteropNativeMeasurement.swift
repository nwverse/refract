import SwiftUI

protocol MeasurementModel: RefractModel {
    var rows: [SettingRow] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct SettingRow: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

struct MeasurementRow: View {
    let model: MeasurementModel

    var body: some View {
        refractView(
            ios: {
                VStack {
                    Text(verbatim: "Settings").font(DesignTypography.rowTitle)
                    List(model.rows) { row in
                        Toggle("settings.item\(row.id)", isOn: Binding(
                            get: { row.enabled },
                            set: { value in model.setEnabled(row.id, value: value) }
                        ))
                        .accessibilityLabel(row.title)
                    }
                }
                .padding(horizontal: 16, vertical: 8)
            },
            android: {
                VStack {
                    Text(verbatim: "Settings").font(DesignTypography.rowTitle)
                    List(model.rows) { row in
                        Toggle("settings.item\(row.id)", isOn: Binding(
                            get: { row.enabled },
                            set: { value in model.setEnabled(row.id, value: value) }
                        ))
                        .refractNativeModifier(
                            .testTag("settings_toggle"),
                            .contentDescription(row.title),
                            .retainCallback(identity: "settings.setEnabled")
                        )
                    }
                }
                .padding(horizontal: 16, vertical: 8)
            },
            harmonyOS: {
                VStack {
                    Text(verbatim: "Settings").font(DesignTypography.rowTitle)
                    List(model.rows) { row in
                        Toggle("settings.item\(row.id)", isOn: Binding(
                            get: { row.enabled },
                            set: { value in model.setEnabled(row.id, value: value) }
                        ))
                        .accessibilityLabel(row.title)
                        .refractNativeModifier(.testTag("settings_toggle"))
                    }
                }
                .padding(horizontal: 16, vertical: 8)
            }
        )
    }
}
