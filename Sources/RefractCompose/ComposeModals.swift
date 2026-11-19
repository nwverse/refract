import RefractIR

extension ComposeBackend {
    func emitModals(_ modals: [ModalPresentation], into out: inout KotlinWriter,
                    context: inout Context) throws {
        for modal in modals {
            let dismissal = try modalDismissal(modal, context: context)
            switch modal.kind {
            case .sheet:
                context.imports.insert("androidx.compose.material3.ModalBottomSheet")
                out.open("if (\(modal.stateName))")
                out.open("ModalBottomSheet(onDismissRequest = { \(dismissal) })")
                for child in modal.content {
                    try emit(child, into: &out, context: &context)
                }
                out.close()
                out.close()
            case .alert:
                guard let title = modal.title, let message = modal.message,
                      let confirmTitle = modal.confirmTitle, let cancelTitle = modal.cancelTitle,
                      let action = modal.confirmAction else {
                    throw Diagnostic(code: "RFMODAL002",
                        message: "A confirmation alert needs its complete typed title, message and action contract.",
                        suggestion: "Use the bounded alert frontend rather than constructing incomplete modal IR")
                }
                context.imports.insert("androidx.compose.material3.AlertDialog")
                context.imports.insert("androidx.compose.material3.TextButton")
                context.imports.insert("androidx.compose.runtime.LaunchedEffect")
                out.open("if (\(modal.stateName))")
                out.line("LaunchedEffect(Unit) {")
                out.depth += 1
                out.line("on\(modal.stateName.uppercasingFirst())Present()")
                out.depth -= 1
                out.line("}")
                out.line("AlertDialog(")
                out.depth += 1
                out.line("onDismissRequest = { \(dismissal) },")
                out.line("confirmButton = {")
                out.depth += 1
                out.line("TextButton(onClick = {")
                out.depth += 1
                out.line(dismissal)
                out.line(try renderAction(action, context: &context))
                out.depth -= 1
                out.line("}) {")
                out.depth += 1
                try emit(.text(confirmTitle, modifiers: [], location: confirmTitle.location), into: &out, context: &context)
                out.depth -= 1
                out.line("}")
                out.depth -= 1
                out.line("},")
                out.line("dismissButton = {")
                out.depth += 1
                out.open("TextButton(onClick = { \(dismissal) })")
                try emit(.text(cancelTitle, modifiers: [], location: cancelTitle.location), into: &out, context: &context)
                out.close()
                out.depth -= 1
                out.line("},")
                out.line("title = {")
                out.depth += 1
                try emit(.text(title, modifiers: [], location: title.location), into: &out, context: &context)
                out.depth -= 1
                out.line("},")
                out.line("text = {")
                out.depth += 1
                try emit(.text(message, modifiers: [], location: message.location), into: &out, context: &context)
                out.depth -= 1
                out.line("},")
                out.depth -= 1
                out.line(")")
                out.close()
            }
        }
    }

    private func modalDismissal(_ modal: ModalPresentation, context: Context) throws -> String {
        for state in context.module.screens.flatMap(\.states) {
            switch state {
            case let .state(name, .bool, _, _) where name == modal.stateName && !modal.isBinding:
                return "\(name) = false"
            case let .binding(name, .bool, _) where name == modal.stateName && modal.isBinding:
                return "on\(name.uppercasingFirst())Change(false)"
            default: continue
            }
        }
        throw Diagnostic(code: "RFMODAL001",
            message: "Native modal dismissal cannot find the declared Boolean owner `\(modal.stateName)`.",
            suggestion: "Validate a distinct @State or @Binding Boolean owner in the frontend")
    }
}
