import SwiftUI

struct OptionalDragItem: Identifiable {
    let id: String
    let title: String
}

protocol OptionalDragModel: RefractModel {
    var items: [OptionalDragItem] { get }
    func receiveDrop(kind: String, payload: String)
}

struct OptionalNativeList: View {
    let model: OptionalDragModel
    let title: String?

    var body: some View {
        if let value = title {
            List {
                ForEach(model.items) { item in
                    Text(value)
                        .refractNativeModifier(.dragPayload(kind: "note", value: value))
                }
            }
        } else {
            Text(verbatim: "Empty")
        }
    }
}
