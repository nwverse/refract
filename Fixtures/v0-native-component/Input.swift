import SwiftUI

struct RoutePreview: RefractNativeView {
    let zoom: Double
    let showsTraffic: Bool

    var body: some View {
        Text("Route at \(zoom), traffic: \(showsTraffic)")
    }
}

struct NativeComponentScreen: View {
    var body: some View {
        RoutePreview(zoom: 12.0, showsTraffic: true)
    }
}
