import SwiftUI

protocol SelectionDropModel: RefractModel {
    func replaceSelection(start: Int, end: Int, replacement: String)
    func receiveDrop(kind: String, payload: String)
}

struct SelectionDropScreen: View {
    let model: SelectionDropModel
    @State private var draft: String = ""
    @State private var dragNote: String = "🌸 汉字"

    var body: some View {
        TextField("settings.display.name", text: $draft)
            .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
    }
}
