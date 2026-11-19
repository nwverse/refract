import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitToggle(title: Expression, value: Expression, modifiers: [Modifier], nativeModifiers: [NativeModifier], isRoot: Bool,
                    labelsHidden: Bool, location: SourceLocation?, into out: inout KotlinWriter,
                    context: inout Context) throws {
        if !labelsHidden {
            context.imports.insert("androidx.compose.foundation.layout.Arrangement")
            context.imports.insert("androidx.compose.foundation.layout.Row")
        }
        context.imports.insert("androidx.compose.material3.Switch")
        if !labelsHidden { context.imports.insert("androidx.compose.material3.Text") }
        let retained = nativeModifiers.contains {
            if case .retainCallback = $0.operation { return true }
            return false
        }
        if retained {
            try emitRetainedToggle(value, into: &out, context: &context)
        }
        let modifierChain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        if labelsHidden, !modifiers.isEmpty {
            throw Diagnostic(code: "RFVIEW003",
                message: "A hidden-label Toggle has no label row to receive these modifiers.",
                suggestion: "Apply layout modifiers to the enclosing stack and native measurement directly to the control.",
                location: location)
        }
        if !labelsHidden {
            out.line("Row(")
            out.depth += 1
            out.line("modifier = \(modifierChain),")
            out.line("horizontalArrangement = Arrangement.SpaceBetween,")
            out.depth -= 1
            out.line(") {")
            out.depth += 1
        }
        if !labelsHidden {
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
        }
        let checked = try renderExpression(value, context: &context)
        let onChange: String
        switch value.value {
        case let .valueProperty(.state(name)):
            onChange = "{ value -> \(name) = value }"
        case let .valueProperty(.binding(name)):
            onChange = "on\(name.uppercasingFirst())Change"
        case let .valueProperty(.itemBinding(binding)):
            onChange = retained ? "onCheckedChange"
                : "{ enabled -> \(binding.model).\(binding.action)(\(binding.item).\(binding.key), enabled) }"
        default:
            throw Diagnostic(code: "state.invalid_projection", message: "A switch needs a local state, parent binding or typed item binding.",
                             suggestion: "Use a projected Bool state/binding or a checked item model action.", location: value.location)
        }
        let switchModifiers = try nativeModifiers.map { operation -> Modifier in
            switch operation.operation {
            case let .testTag(value):
                context.imports.insert("androidx.compose.ui.platform.testTag")
                return Modifier(name: "nativeTestTag", arguments: [value], argumentLabels: [nil], location: operation.location)
            case let .contentDescription(value):
                context.imports.insert("androidx.compose.ui.semantics.contentDescription")
                context.imports.insert("androidx.compose.ui.semantics.semantics")
                return Modifier(name: "nativeContentDescription", arguments: [value], argumentLabels: [nil], location: operation.location)
            case .contentType:
                throw Diagnostic(code: "RFNATIVE004",
                    message: "Row content type belongs on a generated child row, not its Toggle.",
                    suggestion: "Apply `.contentType` directly to the generated child inside a dynamic List",
                    location: operation.location ?? location)
            case .retainCallback:
                return Modifier(name: "retainCallback", location: operation.location)
            case .textSelection, .dragPayload, .dropTarget:
                throw Diagnostic(code: "RFNATIVE005",
                    message: "Selection and drag/drop operations do not apply to a Toggle receiver.",
                    suggestion: "Use a TextField for text selection and a Box-style wrapper for drag/drop.",
                    location: operation.location ?? location)
            }
        }
        let switchChain = try self.modifierChain(switchModifiers, isRoot: false, context: &context)
        out.line("Switch(")
        out.depth += 1
        out.line("checked = \(checked),")
        out.line("onCheckedChange = \(onChange),")
        if switchChain != "Modifier" { out.line("modifier = \(switchChain),") }
        out.depth -= 1
        out.line(")")
        if !labelsHidden { out.close() }
    }

    private func emitRetainedToggle(_ value: Expression, into out: inout KotlinWriter,
                                    context: inout Context) throws {
        guard case let .valueProperty(.itemBinding(binding)) = value.value else {
            throw Diagnostic(code: "RFNATIVE004",
                message: "Toggle callback retention requires the checked typed item action.",
                suggestion: "Use `.retainCallback(identity:)` on a Toggle whose Binding uses the current item's stored id.",
                location: value.location)
        }
        context.imports.insert("androidx.compose.runtime.remember")
        out.open("val onCheckedChange = remember(\(binding.model), \(binding.item).\(binding.key))")
        out.line("{ enabled: Boolean -> \(binding.model).\(binding.action)(\(binding.item).\(binding.key), enabled) }")
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
        case let .formField(form, field):
            guard let declaration = context.form(named: form), declaration.field(named: field) != nil else {
                throw Diagnostic(code: "RFFORM002", message: "Unknown form field `\(form).\(field)`.",
                                 suggestion: "Declare the field in refractForm.", location: value.location)
            }
            let name = "\(form)\(field.uppercasingFirst())"
            let isBinding = context.module.screens.contains { screen in
                screen.states.contains {
                    if case let .form(.binding, declared, _) = $0 { return declared.name == form }
                    return false
                }
            }
            onChange = isBinding ? "on\(name.uppercasingFirst())Change" : "{ value -> \(name) = value }"
        case let .valueProperty(.modelScalarBinding(binding)):
            onChange = "{ value -> \(binding.model).\(binding.action)(value) }"
        default:
            throw Diagnostic(code: "state.invalid_projection",
                             message: "A text field needs a String local state, parent binding or explicit model setter.",
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

    /// Native secure text entry. Material 3 `TextField` keeps platform IME/autofill ownership;
    /// we only select the password keyboard, disable autocorrect and apply the password visual
    /// transformation. The bound String is never written to logs, string resources or composed
    /// into a `Text` label — only the localized placeholder is.
    func emitSecureInput(placeholder: Expression?, value: Expression, reveal: Expression?,
                         modifiers: [Modifier], isRoot: Bool, location: SourceLocation?,
                         into out: inout KotlinWriter, context: inout Context) throws {
        guard let placeholder, case .localizedText = placeholder.value else {
            throw Diagnostic(code: "RFSECURE002",
                             message: "A SecureField needs a localized placeholder key.",
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
            throw Diagnostic(code: "RFSECURE002",
                             message: "A SecureField needs a String local state or parent binding.",
                             suggestion: "Use `text: $name` with String ownership.", location: value.location)
        }
        let modifierChain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        context.imports.insert("androidx.compose.foundation.text.KeyboardOptions")
        context.imports.insert("androidx.compose.material3.Text")
        context.imports.insert("androidx.compose.material3.TextField")
        context.imports.insert("androidx.compose.ui.res.stringResource")
        context.imports.insert("androidx.compose.ui.text.input.KeyboardType")
        context.imports.insert("androidx.compose.ui.text.input.PasswordVisualTransformation")
        context.imports.insert("androidx.compose.ui.text.input.VisualTransformation")
        let transformation: String
        if let reveal {
            let rendered = try renderExpression(reveal, context: &context)
            transformation = "if (\(rendered)) VisualTransformation.None else PasswordVisualTransformation()"
        } else {
            transformation = "PasswordVisualTransformation()"
        }
        out.open("TextField(")
        out.line("value = \(checked),")
        out.line("onValueChange = \(onChange),")
        out.line("label = { Text(text = \(label)) },")
        out.line("visualTransformation = \(transformation),")
        out.line("keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),")
        out.line("modifier = \(modifierChain),")
        out.depth -= 1
        out.line(")")
    }
}
