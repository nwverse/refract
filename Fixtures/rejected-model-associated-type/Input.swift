import SwiftUI

protocol GenericSettingsModel: RefractModel {
    associatedtype Item
}

struct UnsupportedGenericModel: View {
    let model: GenericSettingsModel

    var body: some View {
        Text(verbatim: "Unsupported")
    }
}
