import SwiftUI

struct NativeTextInputHost: RefractTextInputHost {
    @Binding var draft: String
    let focusRequest: Int
    let onDraftCommit: (String) -> Void
    let onCommit: () -> Void

    @FocusState private var isHostFocused: Bool

    var body: some View {
        TextField("Message", text: $draft)
            .focused($isHostFocused)
            .submitLabel(.done)
            .onChange(of: focusRequest) { _, _ in
                isHostFocused = true
            }
            .onSubmit {
                onDraftCommit(draft)
                onCommit()
            }
    }
}

protocol ComposerModel: RefractModel {
    func commitDraft(_ value: String)
    func commit()
}

struct ComposerScreen: View {
    @Binding var draft: String
    @Binding var focusRequest: Int
    let model: ComposerModel

    var body: some View {
        NativeTextInputHost(
            draft: $draft,
            focusRequest: focusRequest,
            onDraftCommit: { value in model.commitDraft(value) },
            onCommit: { model.commit() }
        )
    }
}
