import SwiftUI

protocol StatusModel: RefractModel {
    var title: String { get }
}

struct InvalidStateWrapper: View {
    @EnvironmentObject var model: StatusModel

    var body: some View {
        Text(model.title)
    }
}
