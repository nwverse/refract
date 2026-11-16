import SwiftUI

struct LocalState: View {
    @State private var isEnabled: Bool = false

    var body: some View {
        Toggle("settings.enabled", isOn: $isEnabled)
    }
}
