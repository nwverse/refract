import SwiftUI

struct RejectedOptionalBinding: View {
    var body: some View {
        if let value = Optional(true) {
            Text(verbatim: "Bound")
        }
    }
}
