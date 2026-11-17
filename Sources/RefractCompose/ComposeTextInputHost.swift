import RefractIR
import RefractMapping

/// The host is an application-owned Android View: its InputConnection and composition
/// span never cross the generated component boundary. No string composition mirror exists.
enum ComposeTextInputHost {
    static let symbol = "NativeTextInputHost"

    static func declaration(_ module: Module, location: SourceLocation?) throws -> NativeDeclaration {
        guard let declaration = module.nativeDeclarations.first(where: {
            $0.name == symbol && $0.kind == .textInputHost
        }) else {
            throw Diagnostic(code: "RFINPUT001",
                message: "A native text-input host requires a `RefractTextInputHost` declaration.",
                suggestion: "Declare the bounded native host and its ordinary SwiftUI implementation.",
                location: location)
        }
        return declaration
    }

    static func emit(_ component: NativeComponent, declaration: NativeDeclaration,
                     target: NativeTarget, location: SourceLocation?, isRoot: Bool,
                     modifierParameter: String?, into out: inout KotlinWriter,
                     context: inout ComposeBackend.Context) throws {
        var values: [String: String] = [:]
        var callbacks: [String: String] = [:]
        var writers: [String: String] = [:]
        for argument in component.arguments {
            switch argument.label {
            case "draft":
                let name = try binding(argument.expression, type: .string, location: argument.location)
                values[argument.label] = name
                writers[argument.label] = "on\(name.uppercasingFirst())Change"
            case "focusRequest":
                values[argument.label] = try binding(argument.expression, type: .int, location: argument.location)
            case "onDraftCommit", "onCommit":
                callbacks[argument.label] = try action(argument.expression, location: argument.location)
            default:
                throw unsupported(argument, message: "Unknown text-input host argument.")
            }
        }
        guard let draft = values["draft"], let draftWriter = writers["draft"],
              let focusRequest = values["focusRequest"], let onDraftCommit = callbacks["onDraftCommit"],
              let onCommit = callbacks["onCommit"] else {
            throw Diagnostic(code: "RFINPUT002", message: "The text-input host is missing a required input.",
                suggestion: "Supply draft, focusRequest, onDraftCommit and onCommit.", location: location)
        }
        _ = try InteropMapping.validate(declaration: declaration, target: target, platform: .android,
                                        location: location)
        context.imports.insert("com.example.refract.input.NativeTextInputHost")
        out.open("NativeTextInputHost(")
        out.line("draft = \(draft),")
        out.line("onDraftChange = \(draftWriter),")
        out.line("focusRequest = \(focusRequest),")
        out.line("onDraftCommit = { value -> \(onDraftCommit)(value) },")
        out.line("onCommit = { \(onCommit)() },")
        if isRoot { out.line("\(modifierParameter ?? "modifier") = modifier,") }
        out.depth -= 1
        out.line(")")
    }

    private static func binding(_ expression: Expression, type: ValueType,
                                location: SourceLocation?) throws -> String {
        guard case let .valueProperty(.binding(name)) = expression.value, expression.type == type else {
            throw Diagnostic(code: "RFINPUT002",
                message: "The text-input host requires a parent-owned String draft and Int focus request.",
                suggestion: "Pass @Binding values from the generated screen.", location: location)
        }
        return name
    }

    private static func action(_ expression: Expression, location: SourceLocation?) throws -> String {
        guard case let .reference(name) = expression.value else {
            throw unsupported(expression, message: "A text-input callback must be a declared model action.")
        }
        return name
    }

    private static func unsupported(_ value: Any, message: String) -> Diagnostic {
        Diagnostic(code: "RFINPUT002", message: message,
                   suggestion: "Use the bounded text-input host signature.")
    }
}
