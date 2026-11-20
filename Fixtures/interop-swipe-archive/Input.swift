import SwiftUI

struct ArchiveItem: Identifiable {
    let id: String
    let title: String
}

protocol ArchiveListModel: RefractModel {
    var items: [ArchiveItem] { get }
    func requestArchive(_ identifier: String)
    func archive(_ identifier: String)
    func cancelArchive()
}

struct NativeSwipeArchiveRow: RefractNativeView {
    let identifier: String
    let title: String
    let onRequest: (String) -> Void
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var isConfirming: Bool = false

    var body: some View {
        // The app's ordinary iOS implementation; no generated gesture runtime is shared.
        HStack {
            Text(verbatim: title)
            Button("swipe.archive") { isConfirming = true; onRequest(identifier) }
        }
        .swipeActions(edge: .trailing) {
            Button("swipe.archive") { isConfirming = true; onRequest(identifier) }
        }
        .confirmationDialog("swipe.confirm.title", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("swipe.confirm") { isConfirming = false; onConfirm(identifier) }
            Button("swipe.cancel", role: .cancel) { isConfirming = false; onCancel() }
        } message: {
            Text("swipe.confirm.message")
        }
    }
}

struct ArchiveListScreen: View {
    let model: ArchiveListModel

    var body: some View {
        List(model.items) { item in
            NativeSwipeArchiveRow(
                identifier: item.id,
                title: item.title,
                onRequest: { identifier in model.requestArchive(identifier) },
                onConfirm: { identifier in model.archive(identifier) },
                onCancel: { model.cancelArchive() }
            )
        }
    }
}
