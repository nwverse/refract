import SwiftUI

struct NativeProfileStatusBadge: RefractNativeView {
    var body: some View {
        Label("Settings managed natively", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
