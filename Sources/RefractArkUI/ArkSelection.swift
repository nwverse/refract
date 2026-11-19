import RefractIR

func emitArkSelectionContent(_ content: SelectionContent) throws -> String {
    let links = try content.links.map {
        "new RefractSelectionLink(new RefractSelectionRange(\($0.range.start), \($0.range.end)), \(try ArkText.string($0.destination)))"
    }.joined(separator: ", ")
    return "new RefractSelectionContent(\(try ArkText.string(content.text)), [\(links)])"
}

func emitArkSelectionAction(_ action: StateAction) throws -> String {
    guard case let .modelMethod(model, name, _) = action else {
        throw Diagnostic(code: "RFSELECTION006", message: "Selection callbacks require a declared model action.")
    }
    return "(context: RefractSelectionContext): void => { this.\(model).\(name)(context.range.start, context.range.end, context.text); }"
}
