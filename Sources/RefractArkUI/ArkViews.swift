import RefractIR
import RefractMapping

extension Generation {
    func emitExtended(_ node: ViewNode, into writer: inout ArkWriter, item: String? = nil,
                      lazyOwner: Bool = false, mapping: Mapping = .empty,
                      resolver: InteropResolver? = nil, itemParameters: [String: String] = [:],
                      itemTypeName: String? = nil, traversal: AccessibilityTraversal? = nil,
                      localAliases: Set<String> = [], itemInputs: Set<String> = []) throws {
        switch node {
        case let .layout(layout, children, modifiers, _):
            try emitLayout(layout, children: children, modifiers: modifiers,
                           into: &writer, item: item, mapping: mapping, resolver: resolver,
                           itemTypeName: itemTypeName, localAliases: localAliases)
        case let .scroll(axis, child, modifiers, _):
            writer.open("Scroll()")
            try emit(child, into: &writer, item: item, mapping: mapping, resolver: resolver,
                     localAliases: localAliases)
            writer.close()
            writer.line(".scrollable(\(axis == .horizontal ? "ScrollDirection.Horizontal" : "ScrollDirection.Vertical"))")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .list(children, modifiers, _):
            writer.open("List()")
            for child in children {
                try emit(child, into: &writer, item: item, lazyOwner: true, mapping: mapping, resolver: resolver,
                         localAliases: localAliases)
            }
            writer.close()
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .section(header, children, _):
            writer.open("ListItemGroup(\(try header.map { "{ header: Text(\(try ArkExpression.emit($0, mapping: mapping))) }" } ?? ""))")
            for child in children {
                try emitListItem(child, into: &writer, item: item, mapping: mapping, resolver: resolver,
                                 localAliases: localAliases)
            }
            writer.close()
        case let .listItem(child, _):
            try emitListItem(child, into: &writer, item: item, mapping: mapping, resolver: resolver,
                             localAliases: localAliases)
        case let .horizontalSections(sections, location):
            guard lazyOwner else {
                throw Diagnostic(code: "RFLIST004",
                    message: "Horizontal sections must be a direct List child, not an eager nested container.",
                    suggestion: "Use the bounded Section + horizontal LazyHStack form inside one outer List", location: location)
            }
            try emitHorizontalSections(sections, into: &writer, mapping: mapping, resolver: resolver,
                                       localAliases: localAliases)
        case let .forEach(items, location):
            guard lazyOwner else {
                throw Diagnostic(code: "arkui.lazy_list_owner",
                                 message: "LazyForEach must be a direct child of List.",
                                 suggestion: "Move the dynamic rows into a List, not a stack or ScrollView.",
                                 location: location)
            }
            let source: String
            if let projection = items.projection, case let .valueProperty(.model(model, _)) = items.collection.value {
                source = "this.\(model).\(projection.name)"
            } else {
                source = try ArkExpression.emit(items.collection, mapping: mapping)
            }
            writer.open("LazyForEach(\(source), (\(items.itemName): \(items.itemType)) =>")
            writer.open("ListItem()")
            try emit(items.content, into: &writer, item: items.itemName, mapping: mapping, resolver: resolver,
                     itemTypeName: items.itemType, localAliases: localAliases)
            writer.close()
            let key = "\(items.itemName).\(items.key)"
            writer.close(suffix: ", (\(items.itemName): \(items.itemType)): string => \(items.keyType == .int ? "String(\(key))" : key))")
        case let .image(source, modifiers, _):
            guard let description = source.contentDescription else {
                writer.line("Image(\(try image(source, mapping: mapping)))\(try ArkModifiers.emit(modifiers, item: item, mapping: mapping))")
                return
            }
            writer.line("Image(\(try image(source, mapping: mapping)))")
            writer.depth += 1
            writer.line(".accessibilityText(\(try ArkExpression.emit(description, item: item, mapping: mapping, localAliases: localAliases)))")
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
            writer.depth -= 1
        case let .toggle(title, value, modifiers, nativeModifiers, labelsHidden, _):
            var rowModifiers: [Modifier] = []
            var switchModifiers = try nativeModifiers.map { operation -> Modifier in
                switch operation.operation {
                case let .testTag(value):
                    return Modifier(name: "nativeTestTag", arguments: [value], argumentLabels: [nil], location: operation.location)
                case let .contentDescription(value):
                    return Modifier(name: "accessibilityLabel", arguments: [value], argumentLabels: [nil], location: operation.location)
                case .retainCallback:
                    return Modifier(name: "retainCallback", location: operation.location)
                case let .contentType(value):
                    throw Diagnostic(code: "RFNATIVE004",
                        message: "Row content type `\(value)` belongs on the generated child row, not its Toggle.",
                        suggestion: "Apply `.contentType` directly to the generated child inside a dynamic List",
                        location: operation.location)
                case .textSelection, .dragPayload, .dropTarget:
                    throw Diagnostic(code: "RFNATIVE005",
                        message: "Selection and drag/drop operations do not apply to a Toggle receiver.",
                        suggestion: "Use a TextField for text selection and a Stack-style wrapper for drag/drop.",
                        location: operation.location)
                }
            }
            for modifier in modifiers {
                switch modifier.name {
                case "accessibilityLabel", "accessibilityHint", "accessibilityValue", "accessibilityAction", "accessibilityIdentifier", "nativeTestTag":
                    switchModifiers.append(modifier)
                default:
                    rowModifiers.append(modifier)
                }
            }
            if !labelsHidden {
                writer.open("Row()")
                writer.line("Text(\(try ArkExpression.emit(title, item: item, mapping: mapping)))")
                writer.line("Blank()")
            }
            writer.line("Toggle({ type: ToggleType.Switch, isOn: \(try emitLocalExpression(value, item: item, mapping: mapping, itemParameters: Set(itemParameters.keys), localAliases: localAliases, itemInputs: itemInputs)) })")
            writer.depth += 1
            if case .valueProperty(.itemBinding) = value.value {
                writer.open(".onChange((enabled: boolean) =>")
            } else {
                writer.open(".onChange((value: boolean) =>")
            }
            switch value.value {
            case let .valueProperty(.state(name)):
                writer.line("this.\(name) = value;")
            case let .valueProperty(.binding(name)):
                writer.line("this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(value);")
            case let .valueProperty(.itemBinding(binding)):
                guard (itemTypeName != nil && itemParameters[binding.item] == itemTypeName)
                      || (item == binding.item && itemTypeName != nil)
                      || (item == nil && itemParameters[binding.item] != nil) else {
                    throw Diagnostic(code: "state.invalid_projection", message: "An item toggle must write through its declared item input or current list item.",
                                     suggestion: "Use the declared item input or current LazyForEach item.", location: value.location)
                }
                let isLocal = localAliases.contains(binding.item)
                let receiver = itemInputs.contains(binding.item) && !isLocal ? "this.\(binding.item)" : binding.item
                writer.line("this.\(binding.model).\(binding.action)(\(receiver).\(binding.key), enabled);")
            default:
                throw Diagnostic(code: "state.invalid_projection", message: "An editable toggle needs a local state, parent binding or typed item binding.",
                                 suggestion: "Use a projected Bool state/binding or a checked item model action.", location: value.location)
            }
            writer.close(suffix: ")")
            writer.line(try ArkModifiers.emit(switchModifiers, item: item, mapping: mapping, traversal: traversal), unlessEmpty: true)
            writer.depth -= 1
            if !labelsHidden {
                writer.close()
                writer.line(".justifyContent(FlexAlign.SpaceBetween)")
            }
            writer.line(try ArkModifiers.emit(rowModifiers, item: item, mapping: mapping), unlessEmpty: true)
            if labelsHidden, !rowModifiers.isEmpty {
                throw Diagnostic(code: "RFVIEW003",
                    message: "A hidden-label Toggle has no label row to receive layout modifiers.",
                    suggestion: "Apply layout modifiers to the enclosing stack and measurement directly to the control",
                    location: node.sourceLocation)
            }
        case let .textInput(placeholder, value, modifiers, _):
            var arguments = ["text: \(try emitLocalExpression(value, item: item, mapping: mapping))"]
            if let placeholder { arguments.insert("placeholder: \(try ArkExpression.emit(placeholder, mapping: mapping))", at: 0) }
            writer.line("TextInput({ \(arguments.joined(separator: ", ")) })")
            writer.depth += 1
            writer.open(".onChange((value: string) =>")
            switch value.value {
            case let .valueProperty(.state(name)):
                writer.line("this.\(name) = value;")
            case let .valueProperty(.binding(name)):
                writer.line("this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(value);")
            case let .formField(form, field):
                let name = form + field.prefix(1).uppercased() + String(field.dropFirst())
                let isBinding = module.screens.flatMap(\.states).contains { state in
                    if case let .form(.binding, declared, _) = state { return declared.name == form }
                    return false
                }
                if isBinding {
                    writer.line("this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(value);")
                } else {
                    writer.line("this.\(name) = value;")
                }
            case let .valueProperty(.modelScalarBinding(binding)):
                writer.line("this.\(binding.model).\(binding.action)(value);")
            default:
                throw Diagnostic(code: "state.invalid_projection", message: "A text input needs a String local state, parent binding or explicit model setter.",
                                 suggestion: "Use `text: $name` with String @State or @Binding ownership.", location: value.location)
            }
            writer.close(suffix: ")")
            writer.depth -= 1
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .secureInput(placeholder, value, reveal, modifiers, location):
            var arguments = ["text: \(try emitLocalExpression(value, item: item, mapping: mapping))"]
            if let placeholder {
                guard case .localizedText = placeholder.value else {
                    throw Diagnostic(code: "RFSECURE002", message: "A SecureField needs a localized placeholder key.",
                                     suggestion: "Use a canonical settings.* key.", location: placeholder.location ?? location)
                }
                arguments.insert("placeholder: \(try ArkExpression.emit(placeholder, mapping: mapping))", at: 0)
            }
            writer.line("TextInput({ \(arguments.joined(separator: ", ")) })")
            writer.depth += 1
            // ArkUI secure input: InputType.Password masks glyphs, disables IME suggestions/learning and keeps
            // autofill ownership with the system. Reveal uses InputType.Normal only when the source declared an
            // explicit Bool reveal binding via `.secureReveal($isRevealed)`. The bound String is never logged,
            // formatted into another view or echoed outside this control.
            if let reveal {
                let flag = try emitLocalExpression(reveal, item: item, mapping: mapping)
                writer.line(".type(\(flag) ? InputType.Normal : InputType.Password)")
            } else {
                writer.line(".type(InputType.Password)")
            }
            writer.open(".onChange((value: string) =>")
            switch value.value {
            case let .valueProperty(.state(name)):
                writer.line("this.\(name) = value;")
            case let .valueProperty(.binding(name)):
                writer.line("this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(value);")
            default:
                throw Diagnostic(code: "RFSECURE002", message: "A SecureField needs a String local state or parent binding.",
                                 suggestion: "Use `text: $name` with String @State or @Binding ownership.", location: value.location)
            }
            writer.close(suffix: ")")
            writer.depth -= 1
            writer.line(try ArkModifiers.emit(modifiers, item: item, mapping: mapping), unlessEmpty: true)
        case let .label(title, source, modifiers, _):
            writer.open("Row({ space: 8 })")
            writer.line("Image(\(try image(source, mapping: mapping)))")
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
                              mapping: Mapping = .empty, resolver: InteropResolver? = nil,
                              localAliases: Set<String> = []) throws {
        writer.open("ListItem()")
        if case let .layout(layout, children, modifiers, location) = node {
            // A static List row is a single item; its content stays one native subtree.
            try emitExtended(.layout(layout, children: children, modifiers: modifiers, location: location),
                             into: &writer, item: item, mapping: mapping, resolver: resolver,
                             localAliases: localAliases)
        } else {
            try emit(node, into: &writer, item: item, mapping: mapping, resolver: resolver,
                     localAliases: localAliases)
        }
        writer.close()
    }

    private func image(_ source: ImageSource, mapping: Mapping) throws -> String {
        if source.kind == .system, !mapping.harmonyOS.symbols.isEmpty {
            let symbol = try mapping.symbol(source.name, platform: .harmonyOS, location: source.location)
            guard symbol.kind == .media else {
                throw Diagnostic(code: "RFMAP002", message: "An ArkUI system image must map to an app media resource.",
                                 suggestion: "Use kind `media` with a declared application media name.", location: source.location)
            }
            return "$r('app.media.\(symbol.name)')"
        }
        guard ArkText.isResourceName(source.name) else {
            throw Diagnostic(code: "arkui.invalid_image_resource", message: "`\(source.name)` is not a valid image resource name.",
                             suggestion: "Use a declared ASCII resource identifier.", location: source.location)
        }
        return "$r('\(source.kind == .system ? "sys.media" : "app.media").\(source.name)')"
    }

    private func containerName(_ axis: ViewNode.StackAxis) -> String {
        switch axis { case .vertical: "Column"; case .horizontal: "Row"; case .depth: "Stack" }
    }

}

enum ArkValueType {
    static func emit(_ type: ValueType) -> String {
        switch type {
        case .string: "string"
        case .bool: "boolean"
        case .double, .int: "number"
        case .revision: "bigint"
        }
    }
}
