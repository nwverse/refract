import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitTyped(_ node: ViewNode, isRoot: Bool, parentAxis: ViewNode.StackAxis?,
                   into out: inout KotlinWriter, context: inout Context) throws {
        switch node {
        case let .layout(layout, children, modifiers, _):
            try emitLayout(layout, children: children, modifiers: modifiers, isRoot: isRoot, parentAxis: parentAxis,
                           into: &out, context: &context)
        case let .scroll(axis, child, modifiers, location):
            try emitScroll(axis: axis, child: child, modifiers: modifiers, isRoot: isRoot,
                           location: location, into: &out, context: &context)
        case let .list(children, modifiers, location):
            if children.count == 1, case let .forEach(items, _) = children[0] {
                try emitDynamicList(items, modifiers: modifiers, isRoot: isRoot,
                                    into: &out, context: &context)
            } else {
                try emitStaticList(children, modifiers: modifiers, isRoot: isRoot, location: location,
                                   into: &out, context: &context)
            }
        case let .section(_, _, location):
            throw Diagnostic(code: "RF-C001", message: "A section can only be lowered inside its parent LazyColumn.",
                             suggestion: "Use Section as a direct List child.", location: location)
        case let .listItem(_, location):
            throw Diagnostic(code: "RF-C001", message: "A list item can only be lowered inside its parent LazyColumn.",
                             suggestion: "Use ListItem as a direct List child.", location: location)
        case let .image(source, modifiers, location):
            if context.mapping.android.resources.assetCatalog != nil, let description = source.contentDescription {
                context.imports.insert("androidx.compose.foundation.Image")
                context.imports.insert("androidx.compose.ui.res.painterResource")
                let chain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
                let resource = try composeResource(source.name, kind: .image, mapping: context.mapping,
                                                   location: source.location)
                let label = try renderExpression(description, context: &context)
                out.line("Image(painter = painterResource(\(resource)), contentDescription = \(label), modifier = \(chain))")
                return
            }
            try emitImage(source, modifiers: modifiers, isRoot: isRoot, location: location,
                          into: &out, context: &context)
        case let .label(title, source, modifiers, location):
            try emitLabel(title, source: source, modifiers: modifiers, isRoot: isRoot,
                          location: location, into: &out, context: &context)
        case let .divider(modifiers, _):
            let horizontal = parentAxis != .horizontal
            context.imports.insert(horizontal ? "androidx.compose.material3.HorizontalDivider"
                                               : "androidx.compose.material3.VerticalDivider")
            let chain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
            out.line("\(horizontal ? "HorizontalDivider" : "VerticalDivider")(modifier = \(chain))")
        case .spacer:
            // weight is a RowScope/ColumnScope extension. No foundation.layout.weight import exists publicly.
            let base = parentAxis == .horizontal || parentAxis == .vertical
                ? "Modifier.weight(1f)" : "Modifier"
            context.imports.insert("androidx.compose.foundation.layout.Spacer")
            out.line("Spacer(modifier = \(base))")
        case let .forEach(items, location):
            throw Diagnostic(code: "RF-C003",
                             message: "Dynamic list lowering requires the resolved model collection contract.",
                             suggestion: "Declare an Identifiable item with a stable String or Int id through the model interface.",
                             location: location ?? items.location)
        case let .textInput(placeholder, value, modifiers, location):
            try emitTextInput(placeholder: placeholder, value: value, modifiers: modifiers, isRoot: isRoot,
                              location: location, into: &out, context: &context)
        case let .secureInput(placeholder, value, reveal, modifiers, location):
            try emitSecureInput(placeholder: placeholder, value: value, reveal: reveal,
                                modifiers: modifiers, isRoot: isRoot, location: location,
                                into: &out, context: &context)
        case .stack, .text, .button, .toggle, .native, .nativeModifier, .child, .component, .platformView,
             .conditional, .optionalBinding, .switchExpression, .navigationLink, .navigationStack, .tabView:
            throw Diagnostic(code: "RF-C001", message: "Internal Compose view dispatch is inconsistent.",
                             suggestion: "Report this generator defect.", location: node.sourceLocation)
        }
    }

    private func emitScroll(axis: ViewNode.StackAxis, child: ViewNode, modifiers: [Modifier],
                            isRoot: Bool, location: SourceLocation?, into out: inout KotlinWriter,
                            context: inout Context) throws {
        guard axis != .depth else {
            throw Diagnostic(code: "RF-C001", message: "A depth-axis scroll container has no Compose equivalent.",
                             suggestion: "Use a vertical or horizontal ScrollView.", location: location)
        }
        if case let .list(_, _, listLocation) = child {
            throw Diagnostic(code: "RF-C004",
                             message: "A vertical ScrollView cannot contain a nested LazyColumn.",
                             suggestion: "Use one lazy list, or put fixed-size non-scrolling content inside the ScrollView.",
                             location: listLocation ?? location)
        }
        let chain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        if axis == .vertical {
            context.imports.insert("androidx.compose.foundation.rememberScrollState")
            context.imports.insert("androidx.compose.foundation.verticalScroll")
        } else {
            context.imports.insert("androidx.compose.foundation.rememberScrollState")
            context.imports.insert("androidx.compose.foundation.horizontalScroll")
        }
        let behavior = axis == .vertical ? "verticalScroll" : "horizontalScroll"
        out.open("\(containerName(axis, context: &context))(modifier = \(chain).\(behavior)(rememberScrollState()))")
        try emit(child, parentAxis: axis, into: &out, context: &context)
        out.close()
    }

    private func emitDynamicList(_ items: ListItems, modifiers: [Modifier], isRoot: Bool,
                                into out: inout KotlinWriter, context: inout Context) throws {
        context.imports.insert("androidx.compose.foundation.lazy.LazyColumn")
        context.imports.insert("androidx.compose.foundation.lazy.items")
        out.open("LazyColumn(modifier = \(try modifierChain(modifiers, isRoot: isRoot, context: &context)))")
        try emitDynamicListItems(items, into: &out, context: &context)
        out.close()
    }

    private func emitStaticList(_ children: [ViewNode], modifiers: [Modifier], isRoot: Bool,
                                location: SourceLocation?, into out: inout KotlinWriter,
                                context: inout Context) throws {
        guard children.allSatisfy({ child in
            if case .forEach = child { return false }
            return true
        }) else {
            throw Diagnostic(code: "RF-C003", message: "Static and dynamic rows cannot share this list lowering yet.",
                             suggestion: "Use a model-backed list with a stable item identity.", location: location)
        }
        context.imports.insert("androidx.compose.foundation.lazy.LazyColumn")
        out.open("LazyColumn(modifier = \(try modifierChain(modifiers, isRoot: isRoot, context: &context)))")
        var keys = Set<String>()
        var keyIndex = 0
        for child in children {
            switch child {
            case let .section(header, rows, _):
                if let header {
                    let key = try staticKey(header, prefix: "header", context: &context)
                    guard keys.insert(key).inserted else {
                        throw Diagnostic(code: "RF-C003", message: "Static list item keys must be unique.",
                                         suggestion: "Use distinct section resource keys.", location: header.location)
                    }
                    context.imports.insert("androidx.compose.material3.Text")
                    out.line("item(key = \(key), contentType = \"Header\") { Text(text = \(try renderExpression(header, context: &context))) }")
                }
                for row in rows {
                    let item = try staticItem(row, section: header, index: &keyIndex, context: &context)
                    guard keys.insert(item.key).inserted else {
                        throw Diagnostic(code: "RF-C003", message: "Static list item keys must be unique.",
                                         suggestion: "Use distinct static row resource keys.", location: row.sourceLocation)
                    }
                    out.open("item(key = \(item.key), contentType = \"\(item.contentType)\")")
                    try emit(item.content, parentAxis: .vertical, into: &out, context: &context)
                    out.close()
                }
            case let .listItem(row, _):
                let item = try staticItem(.listItem(child: row, location: child.sourceLocation), section: nil,
                                          index: &keyIndex, context: &context)
                guard keys.insert(item.key).inserted else {
                    throw Diagnostic(code: "RF-C003", message: "Static list item keys must be unique.",
                                     suggestion: "Use distinct static row resource keys.", location: child.sourceLocation)
                }
                out.open("item(key = \(item.key), contentType = \"\(item.contentType)\")")
                try emit(item.content, parentAxis: .vertical, into: &out, context: &context)
                out.close()
            default:
                // Manually constructed IR must not bypass the frontend's static-list row invariant.
                throw Diagnostic(code: "RF-C001", message: "A static LazyColumn requires explicit ListItem rows.",
                                 suggestion: "Wrap each static row in the list frontend's typed ListItem.", location: location)
            }
        }
        out.close()
    }

    private func staticItem(_ node: ViewNode, section: Expression?, index: inout Int,
                            context: inout Context) throws -> (key: String, contentType: String, content: ViewNode) {
        let child: ViewNode
        if case let .listItem(row, _) = node {
            child = row
        } else {
            // Section children are already logical list rows; only top-level List wraps them in ListItem.
            child = node
        }
        defer { index += 1 }
        let key: String
        if case let .text(value, _, _) = child, value.isLocalizedText {
            key = try staticKey(value, prefix: "row", context: &context)
        } else if case let .text(value, _, _) = child, case let .valueProperty(.model(_, property)) = value.value {
            key = "\"row:\(property)\""
        } else if case let .textInput(_, value, _, _) = child, case let .valueProperty(.state(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .textInput(_, value, _, _) = child, case let .valueProperty(.binding(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .secureInput(_, value, _, _, _) = child, case let .valueProperty(.state(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .secureInput(_, value, _, _, _) = child, case let .valueProperty(.binding(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .toggle(_, value, _, _, _, _) = child, case let .valueProperty(.state(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .toggle(_, value, _, _, _, _) = child, case let .valueProperty(.binding(name)) = value.value {
            key = "\"row:\(staticControlIdentity(name))\""
        } else if case let .button(_, action, _, _) = child,
                  case let .modelMethod(_, methodName, arguments)? = action, arguments.isEmpty {
            key = "\"row:\(methodName)\""
        } else {
            throw Diagnostic(code: "RF-C003",
                             message: "This static row has no explicit stable item identity.",
                             suggestion: "Use a resource-keyed Text row or wait for a declared static row identity.",
                             location: child.sourceLocation)
        }
        return (key, contentType(child), child)
    }

    private func staticControlIdentity(_ name: String) -> String {
        // Source state/binding names carry identity across values and recomposition. A terminal
        // `Enabled` suffix is a property-shape marker, not part of the setting's semantic name.
        let semanticName = name.hasSuffix("Enabled") ? String(name.dropLast("Enabled".count)) : name
        var result = ""
        for character in semanticName {
            if character.isUppercase, !result.isEmpty { result.append("-") }
            result.append(character.lowercased())
        }
        return result
    }

    private func staticKey(_ expression: Expression, prefix: String, context: inout Context) throws -> String {
        switch expression.value {
        case let .stringLiteral(value):
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }) else {
                throw Diagnostic(code: "RF-C003", message: "This static list text cannot form a stable portable item key.",
                                 suggestion: "Use a canonical resource key for static list text.", location: expression.location)
            }
            return "\"\(prefix):\(value)\""
        case let .localizedText(text):
            guard LocalizationKey.isCanonical(text.key) else {
                throw Diagnostic(code: "RF-C003", message: "This localized row key is not a canonical stable item identity.",
                                 suggestion: "Use a canonical resource key for static list text.", location: expression.location)
            }
            return "\"\(prefix):\(text.key)\""
        case .stringKey:
            throw Diagnostic(code: "RF-C001", message: "Localized static list keys require frontend localization integration.",
                             suggestion: "Keep the canonical resource key in the typed expression.", location: expression.location)
        default:
            throw Diagnostic(code: "RF-C003", message: "A static list item needs a source-derived stable key.",
                             suggestion: "Use a static resource key or a declared dynamic item id.", location: expression.location)
        }
    }

    private func contentType(_ node: ViewNode) -> String {
        switch node {
        case .text: return "Text"
        case .button: return "Button"
        case .image: return "Image"
        case .label: return "Label"
        case .toggle: return "Toggle"
        case .textInput: return "TextInput"
        case .secureInput: return "SecureInput"
        case .divider: return "Divider"
        case .layout, .stack, .nativeModifier: return "Container"
        case .native: return "Native"
        default: return "Content"
        }
    }

    private func emitImage(_ source: ImageSource, modifiers: [Modifier], isRoot: Bool,
                           location: SourceLocation?, into out: inout KotlinWriter,
                           context: inout Context) throws {
        guard source.kind == .application else {
            guard !context.mapping.android.symbols.isEmpty else {
                throw Diagnostic(code: "RF-C002", message: "SF Symbols have no implicit Android drawable equivalent.",
                                 suggestion: "Use Image(\"drawable_name\") or a declared native component.",
                                 location: location ?? source.location)
            }
            let symbol = try context.mapping.symbol(source.name, platform: .android, location: location ?? source.location)
            switch symbol.kind {
            case .materialIcon:
                let icon = try materialIcon(named: symbol.name, location: location ?? source.location)
                context.imports.insert("androidx.compose.material.icons.Icons")
                context.imports.insert("androidx.compose.material.icons.filled.\(icon)")
                context.imports.insert("androidx.compose.material3.Icon")
                out.line("Icon(imageVector = Icons.Default.\(icon), contentDescription = null)")
            case .drawable:
                guard let resourceClass = context.androidResourceClass, isDrawableName(symbol.name) else {
                    throw Diagnostic(code: "RF-C002", message: "A mapped Android drawable needs a valid R class and resource name.",
                                     suggestion: "Use a declared lowercase drawable and the app's fully qualified R class.",
                                     location: location ?? source.location)
                }
                context.imports.insert("androidx.compose.ui.res.painterResource")
                context.imports.insert("androidx.compose.material3.Icon")
                context.imports.insert(resourceClass)
                out.line("Icon(painter = painterResource(R.drawable.\(symbol.name)), contentDescription = null)")
            case .media:
                throw Diagnostic(code: "RF-C002", message: "A media mapping is only valid for ArkUI.",
                                 suggestion: "Use materialIcon or drawable for Android.", location: location ?? source.location)
            }
            return
        }
        guard let resourceClass = context.androidResourceClass else {
            throw Diagnostic(code: "RF-C002", message: "Application images require the Android R class in refract.json.",
                             suggestion: "Set android.resources.className to the application's fully qualified R class.",
                             location: location ?? source.location)
        }
        guard isDrawableName(source.name) else {
            throw Diagnostic(code: "RF-C002", message: "`\(source.name)` is not a supported Android drawable resource name.",
                             suggestion: "Use a lowercase ASCII drawable identifier with digits and underscores.",
                             location: location ?? source.location)
        }
        if context.mapping.android.resources.assetCatalog != nil {
            _ = try AssetCatalog.resolveBoth(source.name, kind: .image, mapping: context.mapping,
                                             location: location ?? source.location)
        }
        context.imports.insert("androidx.compose.foundation.Image")
        context.imports.insert("androidx.compose.ui.res.painterResource")
        context.imports.insert(resourceClass)
        let chain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        out.line("Image(painter = painterResource(R.drawable.\(source.name)), contentDescription = null, modifier = \(chain))")
    }

    private func emitLabel(_ title: Expression, source: ImageSource, modifiers: [Modifier], isRoot: Bool,
                           location: SourceLocation?, into out: inout KotlinWriter,
                           context: inout Context) throws {
        context.imports.insert("androidx.compose.foundation.layout.Arrangement")
        context.imports.insert("androidx.compose.foundation.layout.Row")
        context.imports.insert("androidx.compose.ui.Alignment")
        context.imports.insert("androidx.compose.ui.unit.dp")
        out.open("Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically)")
        try emitImage(source, modifiers: [], isRoot: false, location: location, into: &out, context: &context)
        context.imports.insert("androidx.compose.material3.Text")
        out.line("Text(text = \(try renderExpression(title, context: &context)))")
        out.close()
    }

    private func materialIcon(named name: String, location: SourceLocation?) throws -> String {
        switch name {
        case "Settings", "Person", "Check": return name
        default:
            throw Diagnostic(code: "RF-C002", message: "Material icon `\(name)` is not in the typed v0 symbol set.",
                             suggestion: "Use Settings, Person or Check, or declare an application drawable instead.",
                             location: location)
        }
    }

    private func containerName(_ axis: ViewNode.StackAxis, context: inout Context) -> String {
        let name = axis == .vertical ? "Column" : axis == .horizontal ? "Row" : "Box"
        context.imports.insert("androidx.compose.foundation.layout.\(name)")
        return name
    }

    private func isDrawableName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }
}
