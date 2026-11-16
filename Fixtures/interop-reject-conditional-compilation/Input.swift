import SwiftUI

struct HiddenPlatformScreen: View {
    var body: some View {
        #if os(iOS)
        Text("iOS")
        #else
        Text("Other")
        #endif
    }
}
