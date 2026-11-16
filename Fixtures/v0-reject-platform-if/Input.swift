import SwiftUI

struct PlatformConditional: View {
    var body: some View {
        #if os(Android)
        Text(verbatim: "Android")
        #else
        Text(verbatim: "Other")
        #endif
    }
}
