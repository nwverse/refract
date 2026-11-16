import SwiftUI

struct RoutePreview: RefractNativeView {
    let zoom: Double

    var body: some View {
        Text("Route preview")
    }
}

struct NativeTypeMismatch: View {
    var body: some View {
        RoutePreview(zoom: 12.0)
    }
}
