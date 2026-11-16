import SwiftUI

struct StyledTextView: View {
    var body: some View {
        VStack {
            Text("Title")
                .font(.title)
                .foregroundColor(.red)
                .padding()
        }
    }
}
