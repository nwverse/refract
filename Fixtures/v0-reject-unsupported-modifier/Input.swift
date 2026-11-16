import SwiftUI

struct UnsupportedModifier: View {
    var body: some View {
        Text(verbatim: "Hello")
            .blur(radius: 4)
    }
}
