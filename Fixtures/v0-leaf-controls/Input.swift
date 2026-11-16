import SwiftUI

protocol ControlsModel: RefractModel {
    func save()
}

struct LeafControls: View {
    let model: ControlsModel

    var body: some View {
        VStack {
            Label("settings.profile", systemImage: "person")
            Image(systemName: "gear")
            Button {
                model.save()
            } label: {
                Label("settings.save", systemImage: "checkmark")
            }
            Divider()
        }
    }
}
