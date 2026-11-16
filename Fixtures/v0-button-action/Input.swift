import SwiftUI

protocol SaveModel: RefractModel {
    func save()
}

struct ButtonAction: View {
    let model: SaveModel

    var body: some View {
        Button("settings.save") {
            model.save()
        }
    }
}
