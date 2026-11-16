import SwiftUI

struct PaddingFormsView: View {
    var body: some View {
        VStack {
            Text("Default").padding()
            Text("Uniform").padding(24)
            Text("Horizontal").padding(.horizontal, 16)
            Text("Edges").padding(.top, 8).padding(.leading, 4)
        }
    }
}
