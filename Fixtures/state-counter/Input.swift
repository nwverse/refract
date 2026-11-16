import SwiftUI

struct Counter: View {
    @State private var count: Int = 0

    var body: some View {
        VStack {
            Text(verbatim: "Count: \(count)")
            Button(verbatim: "Increment") { count += 1 }
        }
    }
}
