import SwiftUI

struct NativeComponentScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.native.component")
            NativeProfileStatusBadge()
        }
        .padding()
    }
}
