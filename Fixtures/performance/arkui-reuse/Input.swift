import SwiftUI

struct SettingRowView: View {
    let title: String
    let subtitle: String
    @Binding var enabled: Bool

    var body: some View {
        HStack {
            VStack {
                Text(title)
                Text(subtitle)
            }
            Toggle("Enabled", isOn: $enabled)
        }
    }
}
