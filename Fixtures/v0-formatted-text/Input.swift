import SwiftUI

protocol CountModel: RefractModel {
    var count: Int { get }
}

struct FormattedText: View {
    let model: CountModel

    var body: some View {
        Text("settings.item.count \(model.count) items")
    }
}
