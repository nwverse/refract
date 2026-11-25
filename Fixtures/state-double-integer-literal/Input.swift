import SwiftUI

struct Progress: View {
    @State private var progress: Double = 0

    var body: some View {
        VStack {
            Text(verbatim: "Progress: \(progress)")
            Button { progress += 1.5 } label: {
                Text(verbatim: "Advance")
            }
        }
    }
}
