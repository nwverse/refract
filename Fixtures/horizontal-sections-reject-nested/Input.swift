import SwiftUI

struct GalleryItem: Identifiable {
    let id: String
    let title: String
}

struct GallerySection: Identifiable {
    let id: String
    let title: String
    let items: [GalleryItem]
}

protocol GalleryModel: RefractModel {
    var sections: [GallerySection] { get }
}

struct GalleryScreen: View {
    let model: GalleryModel

    var body: some View {
        List {
            ForEach(model.sections) { section in
                Section(section.title) {
                    ScrollView {
                        LazyHStack {
                            ForEach(section.items) { item in
                                Text(item.title)
                            }
                        }
                    }
                }
            }
        }
    }
}
