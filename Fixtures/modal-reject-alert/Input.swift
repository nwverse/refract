import SwiftUI

protocol DeleteModel: RefractModel {
    func confirmDelete()
}

struct ModalAlertScreen: View {
    let model: DeleteModel
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
        VStack {
            Text(verbatim: "Profile")
        }
        .alert("modal.delete.title", isPresented: $showDeleteConfirmation) {
                Button("modal.delete.confirm") { model.confirmDelete() }
            }
    }
}
