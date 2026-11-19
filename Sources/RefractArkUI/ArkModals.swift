import RefractIR
import RefractMapping

extension Generation {
    func emitModalBuilders(_ screen: Screen, into writer: inout ArkWriter) throws {
        for modal in screen.modals where modal.kind == .sheet {
            guard modal.content.count == 1, let content = modal.content.first else {
                throw Diagnostic(code: "RFMODAL001", message: "An ArkUI sheet needs one supported content root.",
                                 suggestion: "Use a single view from the bounded sheet-content subset")
            }
            writer.line()
            writer.open("@Builder \(sheetBuilderName(modal))()")
            try emit(content, into: &writer, mapping: mapping,
                     resolver: InteropResolver(module: module, mapping: mapping))
            writer.close()
        }
    }

    func emitModalAttachment(_ modal: ModalPresentation, for screen: Screen, into writer: inout ArkWriter) throws {
        guard modal.kind == .sheet else {
            guard modal.title != nil, modal.message != nil, modal.confirmTitle != nil,
                  modal.cancelTitle != nil, modal.confirmAction != nil else {
                throw Diagnostic(code: "RFMODAL002", message: "The alert's native host contract is incomplete.")
            }
            return
        }
        writer.line(".bindSheet(this.\(modal.stateName), this.\(sheetBuilderName(modal))(), {")
        writer.depth += 1
        writer.line("onWillDismiss: (action: DismissSheetAction): void => {")
        writer.depth += 1
        writer.line("action.dismiss();")
        writer.line(try modalDismissal(modal, screen: screen))
        writer.depth -= 1
        writer.line("},")
        writer.depth -= 1
        writer.line("})")
    }

    func emitModalObservers(_ screen: Screen, into writer: inout ArkWriter) {
        for modal in screen.modals where modal.kind == .alert {
            writer.line("@Monitor('\(modal.stateName)') on\(modal.stateName.prefix(1).uppercased())\(modal.stateName.dropFirst())Changed(monitor: IMonitor): void {")
            writer.depth += 1
            writer.line("if (this.\(modal.stateName)) {")
            writer.depth += 1
            writer.line("this.on\(modal.stateName.prefix(1).uppercased())\(modal.stateName.dropFirst())Present();")
            writer.depth -= 1
            writer.line("}")
            writer.depth -= 1
            writer.line("}")
        }
    }

    func emitInitialModalPresentation(_ screen: Screen, into writer: inout ArkWriter) {
        for modal in screen.modals where modal.kind == .alert {
            writer.line("if (this.\(modal.stateName)) {")
            writer.depth += 1
            writer.line("this.on\(modal.stateName.prefix(1).uppercased())\(modal.stateName.dropFirst())Present();")
            writer.depth -= 1
            writer.line("}")
        }
    }

    private func sheetBuilderName(_ modal: ModalPresentation) -> String {
        "\(modal.stateName)SheetContent"
    }

    private func modalDismissal(_ modal: ModalPresentation, screen: Screen) throws -> String {
        for state in screen.states {
            switch state {
            case let .state(name, .bool, _, _) where name == modal.stateName && !modal.isBinding:
                return "this.\(name) = false;"
            case let .binding(name, .bool, _) where name == modal.stateName && modal.isBinding:
                return "this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(false);"
            default: continue
            }
        }
        throw Diagnostic(code: "RFMODAL001",
            message: "Native modal dismissal cannot find the declared Boolean owner `\(modal.stateName)`.",
            suggestion: "Use a declared Boolean @State or @Binding")
    }
}
