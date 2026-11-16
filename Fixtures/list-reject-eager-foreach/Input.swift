import SwiftUI

struct EagerForEach: View {
    var body: some View {
        List {
            ForEach(0..<10) { index in
                Text(verbatim: "Row")
            }
        }
    }
}
