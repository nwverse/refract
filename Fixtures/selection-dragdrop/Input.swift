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
        VStack {
            refractView(
                ios: {
                    TextField("settings.display.name", text: $draft)
                        .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
                },
                android: {
                    TextField("settings.display.name", text: $draft)
                        .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
                },
                harmonyOS: { TextField("settings.display.name", text: $draft) }
            )
            Text(verbatim: "Drag me")
                .refractNativeModifier(.dragPayload(kind: "note", value: dragNote))
            Text(verbatim: "Drop here")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
}
