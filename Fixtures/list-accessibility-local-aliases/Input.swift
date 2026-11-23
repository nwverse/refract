import SwiftUI

struct AccessibleRowItem: Identifiable {
    let id: Int
    let enabled: Bool
}

protocol AccessibleRowModel: RefractModel {
    var rows: [AccessibleRowItem] { get }
    func setEnabled(_ id: Int, value: Bool)
}

struct AccessibleRowAliases: View {
    let model: AccessibleRowModel
    let description: String?

    var body: some View {
        if let value = description {
            List {
                ForEach(model.rows) { row in
                    VStack {
                        Toggle("settings.item\(row.id)", isOn: Binding(
                            get: { row.enabled },
                            set: { enabled in model.setEnabled(row.id, value: enabled) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(Text(value))
                        .accessibilityHint(Text(value))
                        .accessibilityValue(Text(value))
                        Label("settings.profile", systemImage: "person")
                            .accessibilityLabel(Text(value))
                            .accessibilityHint(Text(value))
                            .accessibilityValue(Text(value))
                        Divider()
                            .accessibilityLabel(Text(value))
                            .accessibilityHint(Text(value))
                            .accessibilityValue(Text(value))
                    }
                    .accessibilityLabel(Text(value))
                    .accessibilityHint(Text(value))
                    .accessibilityValue(Text(value))
                }
            }
            ScrollView {
                Text("settings.profile")
            }
            .accessibilityLabel(Text(value))
            .accessibilityHint(Text(value))
            .accessibilityValue(Text(value))
        } else {
            Text(verbatim: "Empty")
        }
    }
}
