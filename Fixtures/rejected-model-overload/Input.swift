import SwiftUI

protocol SettingsModel: RefractModel {
    var title: String { get }
    func update(_ value: Bool)
    func update(with value: Bool)
}

struct ModelOverloadScreen: View {
    let model: SettingsModel
    var body: some View { Text(model.title) }
}
