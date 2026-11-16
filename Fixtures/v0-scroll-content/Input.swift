import SwiftUI

struct ScrollContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(verbatim: "First")
                Text(verbatim: "Second")
            }
        }
    }
}
