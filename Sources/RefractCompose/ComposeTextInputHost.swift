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
                     context: inout ComposeBackend.Context, backend: ComposeBackend) throws {
        var values: [String: String] = [:]
        var callbacks: [String: String] = [:]
        var writers: [String: String] = [:]
        for argument in component.arguments {
            switch argument.label {
            case "draft":
                let name = try binding(argument.expression, type: .string, nativeType: argument.type,
                                       location: argument.location)
                values[argument.label] = name
                writers[argument.label] = "on\(name.uppercasingFirst())Change"
            case "focusRequest":
                values[argument.label] = try binding(argument.expression, type: .int, nativeType: argument.type,
                                                      location: argument.location)
            case "onDraftCommit":
                guard case let .modelMethod(model, name, arguments)? = argument.action, arguments.isEmpty else {
                    throw unsupported(argument, message: "The draft callback needs a typed String model action.")
                }
                callbacks[argument.label] = "\(model).\(name)"
            case "onCommit":
                guard let action = argument.action else {
                    throw unsupported(argument, message: "The commit callback needs a typed model action.")
                }
                callbacks[argument.label] = try backend.renderAction(action, context: &context)
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
        if !target.module.isEmpty {
            context.imports.insert("\(target.module).\(target.symbol)")
        } else if target.symbol == Self.symbol {
            context.imports.insert("com.example.refract.input.\(Self.symbol)")
        }
        let modifierArgument = isRoot ? "\(modifierParameter ?? "modifier") = modifier" : nil
        var labels: [String: String] = [:]
        for binding in target.arguments {
            guard let label = binding.target else {
                throw unsupported(binding, message: "Every host mapping needs an explicit target label.")
            }
            labels[binding.source] = label
        }
        let draftLabel = try label("draft", labels)
        out.open("\(target.symbol)(")
        out.line("\(draftLabel) = \(draft),")
        out.line("on\(draftLabel.uppercasingFirst())Change = \(draftWriter),")
        out.line("\(try label("focusRequest", labels)) = \(focusRequest),")
        out.line("\(try label("onDraftCommit", labels)) = { value -> \(onDraftCommit)(value) },")
        out.line("\(try label("onCommit", labels)) = { \(onCommit) },")
        if let modifierArgument { out.line("\(modifierArgument),") }
        out.depth -= 1
        out.line(")")
    }

    private static func binding(_ expression: Expression?, type: ValueType, nativeType: NativeParameterType?,
                                location: SourceLocation?) throws -> String {
        guard let expression, case let .valueProperty(.binding(name)) = expression.value, nativeType?.scalar == type else {
            throw Diagnostic(code: "RFINPUT002",
                message: "The text-input host requires a parent-owned String draft and Int focus request.",
                suggestion: "Pass @Binding values from the generated screen.", location: location)
        }
        return name
    }

    private static func label(_ source: String, _ labels: [String: String]) throws -> String {
        guard let label = labels[source] else {
            throw Diagnostic(code: "RFINPUT002", message: "The host mapping has no target label for `\(source)`.",
                           suggestion: "Bind every source-owned host parameter explicitly.")
        }
        return label
    }

    private static func unsupported(_ value: Any, message: String) -> Diagnostic {
        Diagnostic(code: "RFINPUT002", message: message,
                   suggestion: "Use the bounded text-input host signature.")
    }
}
