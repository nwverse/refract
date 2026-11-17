import SwiftUI

struct Counter: View {
    @State private var count: Int = 0

    var body: some View {
        VStack {
            Text(verbatim: "Count: \(count)")
            Button { count += 1 } label: {
                Text(verbatim: "Increment")
            }
        }
    }
}
