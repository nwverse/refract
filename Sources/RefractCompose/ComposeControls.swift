import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitToggle(title: Expression, value: Expression, modifiers: [Modifier], isRoot: Bool,
                    location: SourceLocation?, into out: inout KotlinWriter,
                    context: inout Context) throws {
        context.imports.insert("androidx.compose.foundation.layout.Arrangement")
        context.imports.insert("androidx.compose.foundation.layout.Row")
        context.imports.insert("androidx.compose.material3.Switch")
        context.imports.insert("androidx.compose.ui.res.stringResource")
        let modifierChain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        out.line("Row(")
        out.depth += 1
        out.line("modifier = \(modifierChain),")
        out.line("horizontalArrangement = Arrangement.SpaceBetween,")
        out.depth -= 1
        out.line(") {")
        out.depth += 1
        guard case let .stringKey(key) = title.value else {
            throw Diagnostic(code: "RFSTATE003", message: "A toggle title must be a localization key.",
                             suggestion: "Use a canonical settings.* key.", location: location)
        }
        let resource = try context.mapping.stringResource(key, platform: .android, location: title.location)
        guard let className = resource.className else {
            throw Diagnostic(code: "R.string.invalid_resource", message: "Android string resources need a generated R class name.",
                             suggestion: "Declare resources.className in refract.json.", location: title.location)
        }
        out.line("Text(text = stringResource(\(className).string.\(resource.nativeName))")
        let checked = try renderExpression(value, context: &context)
        let onChange: String
        switch value.value {
        case let .valueProperty(.state(name)):
            onChange = "{ value -> \(name) = value }"
        case let .valueProperty(.binding(name)):
            onChange = "on\(name.uppercasingFirst())Change"
        default:
            throw Diagnostic(code: "RFSTATE003", message: "A switch needs a local state or parent binding.",
                             suggestion: "Use a projected Bool state or binding.", location: value.location)
        }
        out.line("Switch(")
        out.depth += 1
        out.line("checked = \(checked),")
        out.line("onCheckedChange = \(onChange),")
        out.depth -= 1
        out.line(")")
        out.close()
    }
}
