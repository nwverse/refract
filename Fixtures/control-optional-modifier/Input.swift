import SwiftUI

struct OptionalModifier: View {
    let title: String?

    var body: some View {
        if let value = title {
            Text(value).frame(width: 44)
        } else {
            Text("content.empty")
        }
    }
}
