import SwiftUI

struct ImplicitIdentity: View {
    let titles: [String]

    var body: some View {
        List(titles, id: \.self) { title in
            Text(title)
        }
    }
}
