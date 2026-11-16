import RefractIR

extension ComposeBackend {
    func emitLayout(_ layout: LayoutContainer, children: [ViewNode], modifiers: [Modifier],
                    isRoot: Bool, parentAxis: ViewNode.StackAxis?, into out: inout KotlinWriter, context: inout Context) throws {
        let container = switch layout.axis {
        case .vertical: ("Column", "horizontalAlignment", "verticalArrangement")
        case .horizontal: ("Row", "verticalAlignment", "horizontalArrangement")
        case .depth: ("Box", "contentAlignment", "")
        }
        var arguments = ["modifier = \(try modifierChain(modifiers, isRoot: isRoot, parentAxis: parentAxis, context: &context))"]
        if let alignment = layout.alignment {
            context.imports.insert("androidx.compose.ui.Alignment")
            arguments.append("\(container.1) = \(try composeAlignment(alignment, axis: layout.axis))")
        }
        if let spacing = layout.spacing {
            let value: String
            switch spacing.value {
            case let .layoutSpacing(token): value = String(token.points)
            case let .numberLiteral(number):
                guard Double(number) != nil else {
                    throw Diagnostic(code: "RFVIEW003", message: "Stack spacing is not a finite scalar value.",
                                     suggestion: "Use a numeric spacing value or `.small`/`.medium`.",
                                     location: spacing.location)
                }
                value = number
            default:
                throw Diagnostic(code: "RFVIEW003",
                                 message: "Stack spacing is not a resolved scalar or layout token.",
                                 suggestion: "Use a numeric spacing value or `.small`/`.medium`.",
                                 location: spacing.location)
            }
            if value != "0" {
            context.imports.insert("androidx.compose.foundation.layout.Arrangement")
            context.imports.insert("androidx.compose.ui.unit.dp")
            arguments.append("\(container.2) = Arrangement.spacedBy(\(value).dp)")
            }
        }
        context.imports.insert("androidx.compose.foundation.layout.\(container.0)")
        out.line("\(container.0)(\(arguments.joined(separator: ", "))) {")
        out.depth += 1
        for child in children {
            try emit(child, parentAxis: layout.axis, into: &out, context: &context)
        }
        out.close()
    }

    private func composeAlignment(_ alignment: LayoutAlignment, axis: ViewNode.StackAxis) throws -> String {
        switch (axis, alignment) {
        case (.vertical, .leading): "Alignment.Start"
        case (.vertical, .trailing): "Alignment.End"
        case (.vertical, .center): "Alignment.CenterHorizontally"
        case (.horizontal, .top): "Alignment.Top"
        case (.horizontal, .bottom): "Alignment.Bottom"
        case (.horizontal, .center): "Alignment.CenterVertically"
        case (.depth, .topLeading): "Alignment.TopStart"
        case (.depth, .bottomTrailing): "Alignment.BottomEnd"
        case (.depth, .center): "Alignment.Center"
        default:
            throw Diagnostic(code: "RFVIEW003",
                             message: "Stack alignment `\(alignment.rawValue)` is incompatible with this container axis.",
                             suggestion: "Use an alignment from the stack's documented alignment table.")
        }
    }
}
