import SwiftUI

protocol ProfileModel: RefractModel {
    var title: String { get }
    var isEnabled: Bool { get }
    func setEnabled(_ value: Bool)
}

struct ModelScreen: View {
    let model: ProfileModel

    var body: some View {
        VStack {
            Text(model.title)
            Button("settings.disable") {
                model.setEnabled(false)
            }
        }
    }
}
