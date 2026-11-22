import SwiftUI

struct ShadowGalleryItem: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}
struct ShadowGallerySection: Identifiable {
    let id: String
    let title: String
    let items: [ShadowGalleryItem]
}
protocol ShadowGalleryModel: RefractModel {
    var sections: [ShadowGallerySection] { get }
    func setEnabled(_ id: Int, value: Bool)
}
struct ShadowGalleryToggle: View {
    let model: ShadowGalleryModel
    let item: ShadowGalleryItem
    var body: some View {
        List {
            ForEach(model.sections) { section in
                Section(section.title) {
                    ScrollView(.horizontal) {
                        LazyHStack {
                            ForEach(section.items) { item in
                                Toggle("settings.item\(item.id)", isOn: Binding(
                                    get: { item.enabled },
                                    set: { value in model.setEnabled(item.id, value: value) }
                                ))
                            }
                        }
                    }
                }
            }
        }
    }
}
