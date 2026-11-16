import SwiftUI

protocol StatusModel: RefractModel {
    var isEnabled: Bool { get }
}

struct ConditionalContent: View {
    let model: StatusModel

    var body: some View {
        if model.isEnabled {
            Text("settings.enabled")
        } else {
            Text("settings.disabled")
        }
    }
}
