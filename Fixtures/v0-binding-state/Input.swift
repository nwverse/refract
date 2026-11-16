import SwiftUI

struct BindingState: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle("settings.enabled", isOn: $isEnabled)
    }
}
