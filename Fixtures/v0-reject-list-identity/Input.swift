import SwiftUI

struct MissingIdentity: View {
    let titles: [String]

    var body: some View {
        List(titles) { title in
            Text(title)
        }
    }
}
