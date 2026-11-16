import SwiftUI

struct UndefinedSpacingScreen: View {
    var body: some View {
        VStack(spacing: undefinedValue) {
            Text(verbatim: "content")
        }
    }
}
