import SwiftUI

struct AccessibleImageItem: Identifiable {
    let id: String
}

protocol AccessibleImageModel: RefractModel {
    var items: [AccessibleImageItem] { get }
}

struct AccessibleImageList: View {
    let model: AccessibleImageModel
    let description: String?

    var body: some View {
        if let value = description {
            List {
                ForEach(model.items) { row in
                    Image("profile_photo")
                        .accessibilityLabel(Text(value))
                        .accessibilityHint(Text(value))
                        .accessibilityValue(Text(value))
                        .frame(width: 44)
                }
            }
        } else {
            Text(verbatim: "Empty")
        }
    }
}
