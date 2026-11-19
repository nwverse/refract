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

    var body: some View {
        Text(verbatim: title)
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
                onConfirm: { model.archive(item.id) },
                onCancel: { model.cancelArchive() }
            )
        }
    }
}
