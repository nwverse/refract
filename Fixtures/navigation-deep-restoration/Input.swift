import SwiftUI

enum DeepRoute: Hashable {
    case detail
    case editor
}

protocol DeepNavigationModel: RefractModel {
    var title: String { get }
}

struct DeepDetailScreen: View {
    let model: DeepNavigationModel

    var body: some View {
        VStack {
            Text(verbatim: "Detail")
            NavigationLink("navigation.open.editor", value: DeepRoute.editor)
        }
    }
}

struct DeepEditorScreen: View {
    let model: DeepNavigationModel

    var body: some View {
        Text(verbatim: "Editor")
    }
}

struct DeepNavigationScreen: View {
    let model: DeepNavigationModel
    @State private var path: [DeepRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Text(model.title)
                NavigationLink("navigation.open.detail", value: .detail)
            }
            .navigationDestination(for: DeepRoute.self) { route in
                switch route {
                case .detail:
                    DeepDetailScreen(model: model)
                case .editor:
                    DeepEditorScreen(model: model)
                }
            }
        }
    }
}
