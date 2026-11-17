import SwiftUI

struct ModalItemScreen: View {
    @Binding var showDetail: Bool

    var body: some View {
        VStack {
            Text(verbatim: "Profile")
        }
        .sheet(item: $showDetail) { item in
                Text(verbatim: item.id)
            }
    }
}
