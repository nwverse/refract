import SwiftUI

protocol ProfileModel: RefractModel {
    var summary: String { get }
    func confirmDelete()
}

struct ProfileSheet: View {
    let model: ProfileModel

    var body: some View {
        VStack {
            Text(model.summary)
            Text("modal.sheet.description")
        }
    }
}

struct ModalHostScreen: View {
    let model: ProfileModel
    @Binding var isProfilePresented: Bool
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
        VStack {
            Button("modal.profile.open") { isProfilePresented = true }
            Button("modal.delete.open") { showDeleteConfirmation = true }
        }
        .sheet(isPresented: $isProfilePresented) {
            ProfileSheet(model: model)
        }
        .alert("modal.delete.title", isPresented: $showDeleteConfirmation) {
            Button("modal.delete.confirm") { model.confirmDelete() }
            Button("modal.delete.cancel", role: .cancel) {}
        } message: {
            Text("modal.delete.message")
        }
    }
}
