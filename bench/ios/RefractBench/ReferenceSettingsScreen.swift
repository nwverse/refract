import SwiftUI

/// Independently written native reference. It does not call GeneratedSettingRow
/// or share its View body with the generated implementation.
@MainActor
struct ReferenceSettingsScreen: View {
    @ObservedObject var model: BenchmarkSettingsModel

    var body: some View {
        VStack {
            Text(model.title)
                .font(.title3)
                .padding(16)
            List(model.rows) { row in
                ReferenceSettingRow(
                    id: row.id,
                    title: row.title,
                    subtitle: row.subtitle,
                    enabled: row.enabled,
                    onChange: { model.setEnabled(row.id, value: $0) }
                )
            }
            .listStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(BenchmarkScrollDriver())
    }
}

@MainActor
private struct ReferenceSettingRow: View {
    let id: Int
    let title: String
    let subtitle: String
    let enabled: Bool
    let onChange: @MainActor (Bool) -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
            }
            .layoutPriority(1)
            Toggle(title, isOn: Binding(get: { enabled }, set: { value in
                    Task { @MainActor in onChange(value) }
                }))
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity)
        .padding(horizontal: 16, vertical: 8)
    }
}
