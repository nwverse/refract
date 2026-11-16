import SwiftUI

protocol TitlesModel: RefractModel {
    var titles: [String] { get }
}

struct ImplicitIdentity: View {
    let model: TitlesModel

    var body: some View {
        List(model.titles, id: \.self) { title in
            Text(title)
        }
    }
}
