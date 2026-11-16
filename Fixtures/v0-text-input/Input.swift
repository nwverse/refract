import SwiftUI

struct TextInputState: View {
    @State private var displayName: String = ""

    var body: some View {
        TextField("settings.display.name", text: $displayName)
    }
}
