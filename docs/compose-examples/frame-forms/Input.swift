import SwiftUI

struct FrameFormsView: View {
    var body: some View {
        VStack {
            Text("Fixed")
                .frame(width: 120, height: 40)
            Text("FullWidth")
                .frame(maxWidth: .infinity)
        }
    }
}
