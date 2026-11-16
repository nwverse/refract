import SwiftUI

struct PlatformViewScreen: View {
    var body: some View {
        refractView(
            ios: {
                Text("Status").padding(refractValue(ios: 4, android: 4, harmonyOS: 4))
            },
            android: {
                Text("Status").padding(refractValue(ios: 4, android: 12, harmonyOS: 12))
            },
            harmonyOS: {
                Text("Status").padding(refractValue(ios: 4, android: 12, harmonyOS: 16))
            }
        )
    }
}
