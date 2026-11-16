import RefractIR
import RefractMapping

extension Generation {
    func emitLayout(_ layout: LayoutContainer, children: [ViewNode], modifiers: [Modifier],
                    into writer: inout ArkWriter, item: String?, resolver: InteropResolver?) throws {
        var arguments: [String] = []
        if let spacing = layout.spacing {
            arguments.append("space: \(try ArkExpression.emit(spacing, item: item, mapping: mapping))")
        }
        if layout.axis == .depth, let alignment = layout.alignment {
            arguments.append("alignContent: \(try arkAlignment(alignment, axis: layout.axis))")
        }
        let container = switch layout.axis {
        case .vertical: "Column"
        case .horizontal: "Row"
        case .depth: "Stack"
        }
        writer.open("\(container)(\(arguments.isEmpty ? "" : "{ \(arguments.joined(separator: ", ")) }"))")
        for child in children {
            try emit(child, into: &writer, item: item, resolver: resolver)
        }
        writer.close()
        if layout.axis != .depth, let alignment = layout.alignment {
            writer.line(".alignItems(\(try arkAlignment(alignment, axis: layout.axis)))")
        }
        writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
    }

    private func arkAlignment(_ alignment: LayoutAlignment, axis: ViewNode.StackAxis) throws -> String {
        switch (axis, alignment) {
        case (.vertical, .leading): "HorizontalAlign.Start"
        case (.vertical, .trailing): "HorizontalAlign.End"
        case (.vertical, .center): "HorizontalAlign.Center"
        case (.horizontal, .top): "VerticalAlign.Top"
        case (.horizontal, .bottom): "VerticalAlign.Bottom"
        case (.horizontal, .center): "VerticalAlign.Center"
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
