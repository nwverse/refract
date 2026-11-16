import SwiftUI

struct NativeComponentScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generated screen with a native component")
            NativeProfileStatusBadge()
        }
        .padding()
    }
}
