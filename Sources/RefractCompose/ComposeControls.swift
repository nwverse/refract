import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitToggle(title: Expression, value: Expression, modifiers: [Modifier], isRoot: Bool,
                    location: SourceLocation?, into out: inout KotlinWriter,
                    context: inout Context) throws {
        context.imports.insert("androidx.compose.foundation.layout.Arrangement")
        context.imports.insert("androidx.compose.foundation.layout.Row")
        context.imports.insert("androidx.compose.material3.Switch")
        context.imports.insert("androidx.compose.material3.Text")
        let modifierChain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        out.line("Row(")
        out.depth += 1
        out.line("modifier = \(modifierChain),")
        out.line("horizontalArrangement = Arrangement.SpaceBetween,")
        out.depth -= 1
        out.line(") {")
        out.depth += 1
        if case let .stringKey(key) = title.value {
            context.imports.insert("androidx.compose.ui.res.stringResource")
            let resource = try context.mapping.stringResource(key, platform: .android, location: title.location)
            guard let className = resource.className else {
                throw Diagnostic(code: "R.string.invalid_resource", message: "Android string resources need a generated R class name.",
                                 suggestion: "Declare resources.className in refract.json.", location: title.location)
            }
            let reference = className == "\(context.packageName).R" ? "R" : className
            if reference == "R" { context.imports.insert(className) }
            out.line("Text(text = stringResource(\(reference).string.\(resource.nativeName)))")
        } else {
            guard title.type == .string else {
                throw Diagnostic(code: "state.invalid_projection", message: "A toggle title must be a localized key or typed item interpolation.",
                                 suggestion: "Use a canonical settings.* key or a localized item title.", location: location)
            }
            let rendered = try renderExpression(title, context: &context)
            out.line("Text(text = \(rendered))")
        }
        let checked = try renderExpression(value, context: &context)
        let onChange: String
        switch value.value {
        case let .valueProperty(.state(name)):
            onChange = "{ value -> \(name) = value }"
        case let .valueProperty(.binding(name)):
            onChange = "on\(name.uppercasingFirst())Change"
        case let .valueProperty(.itemBinding(binding)):
            onChange = "{ enabled -> \(binding.model).\(binding.action)(\(binding.item).\(binding.key), enabled) }"
        default:
            throw Diagnostic(code: "state.invalid_projection", message: "A switch needs a local state, parent binding or typed item binding.",
                             suggestion: "Use a projected Bool state/binding or a checked item model action.", location: value.location)
        }
        out.line("Switch(")
        out.depth += 1
        out.line("checked = \(checked),")
        out.line("onCheckedChange = \(onChange),")
        out.depth -= 1
        out.line(")")
        out.close()
    }

    func emitTextInput(placeholder: Expression?, value: Expression, modifiers: [Modifier], isRoot: Bool,
                       location: SourceLocation?, into out: inout KotlinWriter,
                       context: inout Context) throws {
        guard let placeholder, case let .localizedText(text) = placeholder.value else {
            throw Diagnostic(code: "state.invalid_projection",
                             message: "A text field needs a localized placeholder.",
                             suggestion: "Use a canonical settings.* key.", location: location)
        }
        let label = try LocalizedTextEmitter.compose(placeholder, mapping: context.mapping,
                                                      packageName: context.packageName) {
            try renderExpression($0, context: &context)
        }
        let checked = try renderExpression(value, context: &context)
        let onChange: String
        switch value.value {
        case let .valueProperty(.state(name)):
            onChange = "{ value -> \(name) = value }"
        case let .valueProperty(.binding(name)):
            onChange = "on\(name.uppercasingFirst())Change"
        default:
            throw Diagnostic(code: "state.invalid_projection",
                             message: "A text field needs a String local state or parent binding.",
                             suggestion: "Use `text: $name` with String ownership.", location: value.location)
        }
        let modifierChain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        context.imports.insert("androidx.compose.material3.Text")
        context.imports.insert("androidx.compose.material3.TextField")
        context.imports.insert("androidx.compose.ui.res.stringResource")
        out.open("TextField(")
        out.line("value = \(checked),")
        out.line("onValueChange = \(onChange),")
        out.line("label = { Text(text = \(label)) },")
        out.line("modifier = \(modifierChain),")
        out.depth -= 1
        out.line(")")
    }
}
