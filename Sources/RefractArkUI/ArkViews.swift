import RefractIR
import RefractMapping

extension Generation {
    func emitExtended(_ node: ViewNode, into writer: inout ArkWriter, item: String? = nil,
                      lazyOwner: Bool = false, mapping: Mapping = .empty,
                      resolver: InteropResolver? = nil) throws {
        switch node {
        case let .layout(layout, children, modifiers, _):
            var arguments: [String] = []
            if let spacing = layout.spacing { arguments.append("space: \(try ArkExpression.emit(spacing, item: item, mapping: mapping))") }
            if layout.axis == .depth { arguments.append("alignContent: \(alignment(layout))") }
            let name = containerName(layout.axis)
            writer.open("\(name)(\(arguments.isEmpty ? "" : "{ \(arguments.joined(separator: ", ")) }"))")
            for child in children { try emit(child, into: &writer, item: item, mapping: mapping, resolver: resolver) }
            writer.close()
            if layout.axis != .depth { writer.line(".alignItems(\(alignment(layout)))") }
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .scroll(axis, child, modifiers, _):
            writer.open("Scroll()")
            try emit(child, into: &writer, item: item, mapping: mapping, resolver: resolver)
            writer.close()
            writer.line(".scrollable(\(axis == .horizontal ? "ScrollDirection.Horizontal" : "ScrollDirection.Vertical"))")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .list(children, modifiers, _):
            writer.open("List()")
            for child in children { try emit(child, into: &writer, item: item, lazyOwner: true, mapping: mapping, resolver: resolver) }
            writer.close()
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .section(header, children, _):
            writer.open("ListItemGroup(\(try header.map { "{ header: Text(\(try ArkExpression.emit($0, mapping: mapping))) }" } ?? ""))")
            for child in children { try emitListItem(child, into: &writer, item: item, mapping: mapping, resolver: resolver) }
            writer.close()
        case let .listItem(child, _):
            try emitListItem(child, into: &writer, item: item, mapping: mapping, resolver: resolver)
        case let .forEach(items, location):
            guard lazyOwner else {
                throw Diagnostic(code: "arkui.lazy_list_owner",
                                 message: "LazyForEach must be a direct child of List.",
                                 suggestion: "Move the dynamic rows into a List, not a stack or ScrollView.",
                                 location: location)
            }
            writer.open("LazyForEach(\(try ArkExpression.emit(items.collection, mapping: mapping)), (item: \(items.itemType)) =>")
            writer.open("ListItem()")
            try emit(items.content, into: &writer, item: items.itemName, mapping: mapping, resolver: resolver)
            writer.close()
            let key = "item.\(items.key)"
            writer.close(suffix: ", (item: \(items.itemType)): string => \(items.keyType == .int ? "String(\(key))" : key))")
        case let .image(source, modifiers, _):
            writer.line("Image(\(try image(source)))\(try ArkModifiers.emit(modifiers, item: item, mapping: mapping))")
        case let .toggle(title, value, modifiers, _):
            writer.open("Row()")
            writer.line("Text(\(try ArkExpression.emit(title, mapping: mapping)))")
            writer.line("Blank()")
            writer.line("Toggle({ type: ToggleType.Switch, isOn: \(try emitLocalExpression(value)) })")
            writer.depth += 1
            writer.open(".onChange((value: boolean) =>")
            switch value.value {
            case let .valueProperty(.state(name)):
                writer.line("this.\(name) = value;")
            case let .valueProperty(.binding(name)):
                writer.line("this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(value);")
            default:
                throw Diagnostic(code: "state.invalid_projection", message: "An editable toggle needs a local state or parent binding.",
                                 suggestion: "Use a projected Bool @State or @Binding property.", location: value.location)
            }
            writer.close(suffix: ")")
            writer.depth -= 1
            writer.close()
            writer.line(".justifyContent(FlexAlign.SpaceBetween)")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .textInput(placeholder, value, modifiers, _):
            var arguments = ["text: \(try ArkExpression.emit(value, item: item, mapping: mapping))"]
            if let placeholder { arguments.insert("placeholder: \(try ArkExpression.emit(placeholder, mapping: mapping))", at: 0) }
            writer.line("TextInput({ \(arguments.joined(separator: ", ")) })")
            writer.open(".onChange((value: string) =>")
            writer.line("\(try ArkExpression.assignment(value, to: "value"));")
            writer.close(suffix: ")")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .label(title, source, modifiers, _):
            writer.open("Row({ space: 8 })")
            writer.line("Image(\(try image(source)))")
            writer.line("Text(\(try ArkExpression.emit(title, mapping: mapping)))")
            writer.close()
            writer.line(".alignItems(VerticalAlign.Center)")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .divider(modifiers, _):
            writer.line("Divider()\(try ArkModifiers.emit(modifiers, item: item, mapping: mapping))")
        case .spacer:
            writer.line("Blank()")
        default:
            throw Diagnostic(code: "arkui.internal_node_dispatch", message: "Internal ArkUI view dispatch is incomplete.",
                             suggestion: "Report this generator defect.")
        }
    }

    private func emitListItem(_ node: ViewNode, into writer: inout ArkWriter, item: String? = nil,
                              mapping: Mapping = .empty, resolver: InteropResolver? = nil) throws {
        writer.open("ListItem()")
        if case let .layout(layout, children, modifiers, location) = node {
            // A static List row is a single item; its content stays one native subtree.
            try emitExtended(.layout(layout, children: children, modifiers: modifiers, location: location),
                             into: &writer, item: item, mapping: mapping, resolver: resolver)
        } else {
            try emit(node, into: &writer, item: item, mapping: mapping, resolver: resolver)
        }
        writer.close()
    }

    private func image(_ source: ImageSource) throws -> String {
        guard ArkText.isResourceName(source.name) else {
            throw Diagnostic(code: "arkui.invalid_image_resource", message: "`\(source.name)` is not a valid image resource name.",
                             suggestion: "Use a declared ASCII resource identifier.", location: source.location)
        }
        return "$r('\(source.kind == .system ? "sys.media" : "app.media").\(source.name)')"
    }

    private func containerName(_ axis: ViewNode.StackAxis) -> String {
        switch axis { case .vertical: "Column"; case .horizontal: "Row"; case .depth: "Stack" }
    }

    private func alignment(_ layout: LayoutContainer) -> String {
        switch (layout.axis, layout.alignment) {
        case (.vertical, .leading): "HorizontalAlign.Start"
        case (.vertical, .trailing): "HorizontalAlign.End"
        case (.vertical, _): "HorizontalAlign.Center"
        case (.horizontal, .top): "VerticalAlign.Top"
        case (.horizontal, .bottom): "VerticalAlign.Bottom"
        case (.horizontal, _): "VerticalAlign.Center"
        case (.depth, .topLeading): "Alignment.TopStart"
        case (.depth, .bottomTrailing): "Alignment.BottomEnd"
        case (.depth, _): "Alignment.Center"
        }
    }
}

enum ArkValueType {
    static func emit(_ type: ValueType) -> String {
        switch type { case .string: "string"; case .bool: "boolean"; case .double, .int: "number" }
    }
}
