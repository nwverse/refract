import SwiftUI

/// The application owns this native raw-resource implementation.
struct AppPolicyDocument: RefractNativeView {
    let document: RawAsset

    var body: some View { Text(verbatim: "Synthetic policy") }
}

struct TypedAssetScreen: View {
    var body: some View {
        VStack {
            Image("app_logo", label: Text("assets.logo.description"))
            Text("assets.title")
                .font(.custom("app_body", size: 16, relativeTo: .body))
            AppPolicyDocument(document: RawAsset("privacy_policy"))
        }
    }
}
