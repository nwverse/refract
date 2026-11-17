import SwiftUI

struct PlatformValueScreen: View {
    var body: some View {
        VStack {
            Text(verbatim: "Spacing")
                .padding(refractValue(ios: 4, android: 12, harmonyOS: 16))
            Text(verbatim: refractValue(ios: "iOS", android: "Android", harmonyOS: "HarmonyOS"))
        }
    }
}
