import SwiftUI

enum Route: Hashable {
    case detail
}

struct NavigationScreen: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: path[0])
            }
        }
    }
}
