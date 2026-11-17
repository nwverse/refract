import SwiftUI

enum WidthSizeClass {
    case compact
    case expanded
}

enum Route: Hashable {
    case detail
}

struct DetailScreen: View {
    var body: some View {
        Text(verbatim: "Detail")
    }
}

struct InvalidAdaptiveNavigation: View {
    let widthSizeClass: WidthSizeClass
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: .detail)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail:
                    DetailScreen()
                }
            }
        }
    }
}
