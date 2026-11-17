import SwiftUI

struct BadDragScreen: View {
    @State private var note: String = "hello"
    var body: some View {
        // Non-String payload (Int literal standing in for a URI object) must be rejected at parse time.
        Text(verbatim: "Drag")
            .refractNativeModifier(.dragPayload(kind: "note", value: 42))
    }
}
