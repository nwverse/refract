import SwiftUI

struct UnsupportedBinding: View {
    @Binding var isEnabled: Bool = false

    var body: some View {
        Text("Unsupported")
    }
}
