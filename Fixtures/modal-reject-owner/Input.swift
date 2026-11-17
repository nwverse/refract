import SwiftUI

struct ModalOwnerScreen: View {
    @State private var title: String = ""

    var body: some View {
        VStack {
            Text(verbatim: "Profile")
        }
        .sheet(isPresented: $title) {
                Text(verbatim: "Details")
            }
    }
}
