import SwiftUI

struct LocalSheetScreen: View {
    @State private var showDetails: Bool = false

    var body: some View {
        VStack {
            Button("modal.profile.open") { showDetails = true }
        }
        .padding(16)
        .sheet(isPresented: $showDetails) {
            Text("modal.sheet.description")
        }
        .padding(8)
    }
}
