import SwiftUI

protocol TitlesModel: RefractModel {
    var titles: [String] { get }
}

struct MissingIdentity: View {
    let model: TitlesModel

    var body: some View {
        List(model.titles) { title in
            Text(title)
        }
    }
}
