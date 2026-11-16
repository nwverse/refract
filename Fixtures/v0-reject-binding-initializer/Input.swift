import SwiftUI

struct InvalidBinding: View {
    @Binding var isEnabled: Bool = true

    var body: some View {
        Toggle("settings.enabled", isOn: $isEnabled)
    }
}
