import RefractIR
import RefractMapping

extension ArkUIBackend {
    func emitExtended(_ node: ViewNode, into writer: inout ArkWriter, item: String? = nil,
                      lazyOwner: Bool = false, resolver: InteropResolver? = nil) throws {
        switch node {
        case let .layout(layout, children, modifiers, _):
            var arguments: [String] = []
            if let spacing = layout.spacing { arguments.append("space: \(try ArkExpression.emit(spacing, item: item))") }
            if layout.axis == .depth { arguments.append("alignContent: \(alignment(layout))") }
            let name = containerName(layout.axis)
            writer.open("\(name)(\(arguments.isEmpty ? "" : "{ \(arguments.joined(separator: ", ")) }"))")
            for child in children { try emit(child, into: &writer, item: item, resolver: resolver) }
            writer.close()
            if layout.axis != .depth { writer.line(".alignItems(\(alignment(layout)))") }
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .scroll(axis, child, modifiers, _):
            writer.open("Scroll()")
            try emit(child, into: &writer, item: item, resolver: resolver)
            writer.close()
            writer.line(".scrollable(\(axis == .horizontal ? "ScrollDirection.Horizontal" : "ScrollDirection.Vertical"))")
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .list(children, modifiers, _):
            writer.open("List()")
            for child in children { try emit(child, into: &writer, item: item, lazyOwner: true, resolver: resolver) }
            writer.close()
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .section(header, children, _):
            writer.open("ListItemGroup(\(try header.map { "{ header: Text(\(try ArkExpression.emit($0))) }" } ?? ""))")
            for child in children { try emitListItem(child, into: &writer, item: item, resolver: resolver) }
            writer.close()
        case let .listItem(child, _):
            try emitListItem(child, into: &writer, item: item, resolver: resolver)
        case let .forEach(items, location):
            guard lazyOwner else {
                throw Diagnostic(code: "arkui.lazy_list_owner",
                                 message: "LazyForEach must be a direct child of List.",
                                 suggestion: "Move the dynamic rows into a List, not a stack or ScrollView.",
                                 location: location)
            }
            writer.open("LazyForEach(\(try ArkExpression.emit(items.collection)), (item: \(items.itemType)) =>")
            writer.open("ListItem()")
            try emit(items.content, into: &writer, item: items.itemName, resolver: resolver)
            writer.close()
            let key = "item.\(items.key)"
            writer.close(suffix: ", (item: \(items.itemType)): string => \(items.keyType == .int ? "String(\(key))" : key))")
        case let .image(source, modifiers, _):
            writer.line("Image(\(try image(source)))\(try ArkModifiers.emit(modifiers, item: item))")
        case let .toggle(title, value, modifiers, _):
            writer.open("Row()")
            guard let resolver else {
                throw Diagnostic(code: "R.string.not_configured", message: "A localized toggle needs a resolved mapping.",
                                 suggestion: "Provide a version 1 refract.json.", location: title.location)
            }
            writer.line("Text(\(try resourceReference(title, mapping: resolver.mapping)))")
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
                throw Diagnostic(code: "RFSTATE003", message: "An editable toggle needs a local state or parent binding.",
                                 suggestion: "Use a projected Bool @State or @Binding property.", location: value.location)
            }
            writer.close(suffix: ")")
            writer.depth -= 1
            writer.close()
            writer.line(".justifyContent(FlexAlign.SpaceBetween)")
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .textInput(placeholder, value, modifiers, _):
            var arguments = ["text: \(try ArkExpression.emit(value))"]
            if let placeholder { arguments.insert("placeholder: \(try ArkExpression.emit(placeholder))", at: 0) }
            writer.line("TextInput({ \(arguments.joined(separator: ", ")) })")
            writer.open(".onChange((value: string) =>")
            writer.line("\(try ArkExpression.assignment(value, to: "value"));")
            writer.close(suffix: ")")
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .label(title, source, modifiers, _):
            writer.open("Row({ space: 8 })")
            writer.line("Image(\(try image(source)))")
            writer.line("Text(\(try ArkExpression.emit(title)))")
            writer.close()
            writer.line(".alignItems(VerticalAlign.Center)")
            writer.line(try ArkModifiers.emit(modifiers, item: item), unlessEmpty: true)
        case let .divider(modifiers, _):
            writer.line("Divider()\(try ArkModifiers.emit(modifiers, item: item))")
        case .spacer:
            writer.line("Blank()")
        default:
            throw Diagnostic(code: "arkui.internal_node_dispatch", message: "Internal ArkUI view dispatch is incomplete.",
                             suggestion: "Report this generator defect.")
        }
    }

    private func emitListItem(_ node: ViewNode, into writer: inout ArkWriter, item: String? = nil,
                              resolver: InteropResolver? = nil) throws {
        writer.open("ListItem()")
        if case let .layout(layout, children, modifiers, location) = node {
            // A static List row is a single item; its content stays one native subtree.
            try emitExtended(.layout(layout, children: children, modifiers: modifiers, location: location),
                             into: &writer, item: item, resolver: resolver)
        } else {
            try emit(node, into: &writer, item: item, resolver: resolver)
        }
        writer.close()
    }

    private func resourceReference(_ title: Expression, mapping: Mapping) throws -> String {
        guard case let .stringKey(key) = title.value else {
            throw Diagnostic(code: "RFSTATE003", message: "A toggle title must be a canonical localization key.",
                             suggestion: "Use a settings.* key.", location: title.location)
        }
        let resource = try mapping.stringResource(key, platform: .harmonyOS, location: title.location)
        return "$r('\(resource.namespace ?? "app").\(resource.table ?? "string").\(resource.nativeName)')"
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
