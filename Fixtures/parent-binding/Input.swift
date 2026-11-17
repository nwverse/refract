import SwiftUI

struct EnabledRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack {
            Text(verbatim: "Enabled: \(isEnabled)")
            Button { isEnabled = false } label: {
                Text(verbatim: "Disable")
            }
        }
    }
}
