import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol OptionalNativeModel: RefractModel {
    var items: [SettingItem] { get }
}

struct RoutePreview: RefractNativeView {
    let zoom: Double
    let showsTraffic: Bool
    let title: String

    var body: some View {
        Text(verbatim: "Native iOS route preview")
    }
}

struct RouteScreen: View {
    let model: OptionalNativeModel
    let title: String?

    var body: some View {
        VStack {
            Text(verbatim: "Route")
            if let value = title {
                List {
                    ForEach(model.items) { item in
                        RoutePreview(zoom: 12.0, showsTraffic: true, title: value)
                    }
                }
            } else {
                Text(verbatim: "Empty")
            }
        }
    }
}
