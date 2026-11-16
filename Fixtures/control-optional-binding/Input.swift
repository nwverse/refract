import SwiftUI

struct OptionalGreeting: View {
    let title: String?

    var body: some View {
        if let value = title {
            Text(value)
        } else {
            Text("content.empty")
        }
    }
}
