import SwiftUI

struct RoutePreview: RefractNativeView {
    let zoom: Double

    var body: some View {
        Text("Native iOS route preview")
    }
}

struct MismatchedMappingScreen: View {
    var body: some View {
        RoutePreview(zoom: 12.0)
    }
}
