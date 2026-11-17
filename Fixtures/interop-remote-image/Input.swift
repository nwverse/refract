import SwiftUI

struct RemoteImage: RefractNativeView {
    let url: String
    let placeholder: Image
    let failure: Image
    let contentDescription: LocalizedStringKey

    var body: some View {
        // The app may replace this native implementation without changing the screen.
        if let components = URLComponents(string: url),
           components.scheme?.lowercased() == "https",
           components.host?.isEmpty == false,
           components.user == nil, components.password == nil,
           (components.port ?? 0) < 65_536,
           let destination = components.url {
            AsyncImage(url: destination) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image.resizable()
                case .failure:
                    failure
                @unknown default:
                    failure
                }
            }
            .accessibilityLabel(contentDescription)
        } else {
            failure.accessibilityLabel(contentDescription)
        }
    }
}

struct ProfileImage: View {
    let url: String

    var body: some View {
        RemoteImage(
            url: url,
            placeholder: Image("profile_placeholder"),
            failure: Image("profile_unavailable"),
            contentDescription: "profile.photo.description"
        )
    }
}
