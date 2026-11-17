import SwiftUI

enum Route: Hashable {
    case detail(String)
}

protocol DetailModel: RefractModel {
    var title: String { get }
}

struct NavigationScreen: View {
    let model: DetailModel
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: .detail)
            }
        }
    }
}
