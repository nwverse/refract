import SwiftUI

enum Route: Hashable {
    case detail
    case native
}

protocol DetailModel: RefractModel {
    var title: String { get }
}

struct DetailScreen: View {
    let model: DetailModel

    var body: some View {
        Text(model.title)
    }
}

struct NativeDetail: RefractNativeView {
    var body: some View {
        Text(verbatim: "Native iOS detail")
    }
}

struct NavigationScreen: View {
    let model: DetailModel
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: .detail)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail:
                    DetailScreen(model: model)
                case .native:
                    NativeDetail()
                }
            }
        }
    }
}
