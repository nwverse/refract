import SwiftUI

struct BodyMutation: View {
    @State private var count: Int = 0

    var body: some View {
        count += 1
        Text(verbatim: "Hello")
    }
}
