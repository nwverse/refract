import SwiftUI

struct RoutePreview: RefractNativeView {
    let zoom: Double
    let showsTraffic: Bool

    var body: some View {
        Text("Native iOS route preview")
    }
}

struct MissingMappingScreen: View {
    var body: some View {
        RoutePreview(zoom: 12.0, showsTraffic: true)
    }
}
