import SwiftUI

struct NativeDocumentPreview: RefractNativeView {
    let uri: String
    let displayName: String
    let mimeType: String
    let byteCount: Int
    let revision: Int

    var body: some View {
        Text(verbatim: displayName)
    }
}

struct DocumentPreviewScreen: View {
    var body: some View {
        NativeDocumentPreview(
            uri: "file:///synthetic/document.txt",
            displayName: "Synthetic document",
            mimeType: "text/plain",
            byteCount: 0,
            revision: 1,
            decoder: "untyped"
        )
    }
}
