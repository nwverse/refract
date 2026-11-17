import SwiftUI

enum DocumentPreviewState {
    case loading
    case ready
    case missing
    case unsupported
    case cancelled
    case closed
}

protocol DocumentPreviewModel: RefractModel {
    func cancelPreview()
    func closePreview()
}

struct NativeDocumentPreview: RefractNativeView {
    let uri: String
    let displayName: String
    let mimeType: String
    let byteCount: Int
    let revision: Int
    let onClose: () -> Void

    var body: some View {
        // iOS uses this ordinary SwiftUI implementation. It never opens the URI.
        VStack {
            Text(verbatim: displayName)
            Button("document.close") { onClose() }
        }
    }
}

struct DocumentPreviewScreen: View {
    let state: DocumentPreviewState
    let uri: String
    let displayName: String
    let mimeType: String
    let byteCount: Int
    let revision: Int
    let model: DocumentPreviewModel

    var body: some View {
        switch state {
        case .loading:
            VStack {
                Text("document.loading")
                Button("document.cancel") {
                    model.cancelPreview()
                }
            }
        case .ready:
            NativeDocumentPreview(
                uri: uri,
                displayName: displayName,
                mimeType: mimeType,
                byteCount: byteCount,
                revision: revision,
                onClose: { model.closePreview() }
            )
        case .missing:
            Text("document.missing")
        case .unsupported:
            Text("document.unsupported")
        case .cancelled:
            Text("document.cancelled")
        case .closed:
            Text("document.closed")
        }
    }
}
