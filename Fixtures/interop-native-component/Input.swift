import SwiftUI

struct RoutePreview: RefractNativeView {
    let zoom: Double
    let showsTraffic: Bool

    var body: some View {
        Text(verbatim: "Native iOS route preview")
    }
}

struct RouteScreen: View {
    var body: some View {
        VStack {
            Text(verbatim: "Route")
            RoutePreview(zoom: 12.0, showsTraffic: true)
        }
    }
}
