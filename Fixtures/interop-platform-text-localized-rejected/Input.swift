import SwiftUI

struct PlatformTextLocalizedRejected: View {
    var body: some View {
        VStack {
            // Bare `Text(refractValue(...))` is rejected: SwiftUI's Text(_:)
            // treats the iOS String as a localization key, while the native
            // backends already emit it as a verbatim literal. The documented
            // form is `Text(verbatim: refractValue(...))` so all three
            // platforms agree on the literal-text semantics.
            Text(refractValue(ios: "iOS", android: "Android", harmonyOS: "HarmonyOS"))
        }
    }
}
