import SwiftUI

struct OptionalTitleView: View {
    var title: String?

    var body: some View {
        VStack {
            if let title = title {
                Text(title)
            }
        }
    }
}
