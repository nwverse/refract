import SwiftUI

enum EscapeRoute: Hashable {
    case detail
    case native
}

protocol EscapeDetailModel: RefractModel {
    var title: String { get }
}

struct EscapeDetailScreen: View {
    let model: EscapeDetailModel

    var body: some View {
        Text(model.title)
    }
}

struct NativeDetail: RefractNativeView {
    var body: some View {
        Text(verbatim: "Native iOS detail")
    }
}

struct EscapeScreen: View {
    let model: EscapeDetailModel
    @State private var path: [EscapeRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: .detail)
            }
            .navigationDestination(for: EscapeRoute.self) { route in
                switch route {
                case .detail:
                    EscapeDetailScreen(model: model)
                case .native:
                    NativeDetail()
                }
            }
        }
    }
}
