import SwiftUI

struct EnabledRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack {
            Text("Enabled: \(isEnabled)")
            Button("Disable") { isEnabled = false }
        }
    }
}
