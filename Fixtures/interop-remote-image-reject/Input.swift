import SwiftUI

struct RemoteImage: RefractNativeView {
    let url: String
    let placeholder: Image
    let failure: Image
    let contentDescription: LocalizedStringKey
    let loader: RemoteImageLoader

    var body: some View { placeholder }
}

struct BadRemoteImage: View {
    let url: String

    var body: some View {
        RemoteImage(
            url: url,
            placeholder: Image(systemName: "photo"),
            failure: "profile_unavailable",
            contentDescription: url,
            loader: RemoteImageLoader()
        )
    }
}
