import RefractIR

func emitComposeSelectionContent(_ content: SelectionContent) throws -> String {
    let links = try content.links.map {
        "RefractSelectionLink(range = RefractSelectionRange(start = \($0.range.start), end = \($0.range.end)), destination = \"\($0.destination.escapedForKotlin())\")"
    }.joined(separator: ", ")
    return "RefractSelectionContent(text = \"\(content.text.escapedForKotlin())\", links = listOf(\(links)))"
}

func emitComposeSelectionAction(_ action: StateAction) throws -> String {
    guard case let .modelMethod(model, name, _) = action else {
        throw Diagnostic(code: "RFSELECTION006", message: "Selection callbacks require a declared model action.")
    }
    return "{ context -> \(model).\(name)(start = context.range.start, end = context.range.end, text = context.text) }"
}
