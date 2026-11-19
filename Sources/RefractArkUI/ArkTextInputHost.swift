import RefractIR
import RefractMapping

/// The ArkUI host owns TextInputController, native composition and focus. Only
/// committed text crosses this direct call. This is source evidence, not an
/// ArkTS compiler or device-IME claim.
enum ArkTextInputHost {
    static let symbol = "NativeTextInputHost"

    static func emit(_ component: NativeComponent, target: NativeTarget,
                     module: Module, mapping: Mapping, location: SourceLocation?,
                     into writer: inout ArkWriter) throws {
        guard let declaration = module.nativeDeclarations.first(where: {
            $0.name == symbol && $0.kind == .textInputHost
        }) else {
            throw Diagnostic(code: "RFINPUT001", message: "The native text-input host declaration is missing.",
                suggestion: "Declare `NativeTextInputHost: RefractTextInputHost`.", location: location)
        }
        _ = try InteropMapping.validate(declaration: declaration, target: target,
                                        platform: .harmonyOS, location: location)
        _ = mapping
        var values: [String: String] = [:]
        var callbacks: [String: String] = [:]
        for argument in component.arguments {
            switch argument.label {
            case "draft", "focusRequest":
                guard let expression = argument.type,
                      let bindingExpression = argument.expression,
                      case let .valueProperty(.binding(name)) = bindingExpression.value,
                      expression.scalar == (argument.label == "draft" ? .string : .int) else {
                    throw invalid(argument.location, "The draft and focus request must be parent bindings.")
                }
                values[argument.label] = "this.\(name)"
            case "onDraftCommit":
                guard case let .modelMethod(model, name, arguments)? = argument.action, arguments.isEmpty else {
                    throw invalid(argument.location, "The draft callback needs a typed String model action.")
                }
                callbacks[argument.label] = "\(model).\(name)"
            case "onCommit":
                guard let action = argument.action else {
                    throw invalid(argument.location, "The commit callback needs a declared model action.")
                }
                callbacks[argument.label] = try emitLocalAction(action)
            default:
                throw invalid(argument.location, "Unknown text-input host argument.")
            }
        }
        guard let draft = values["draft"], let focusRequest = values["focusRequest"],
              let onDraftCommit = callbacks["onDraftCommit"], let onCommit = callbacks["onCommit"] else {
            throw invalid(location, "The text-input host is missing a required input.")
        }
        writer.line("NativeTextInputHost({")
        writer.depth += 1
        writer.line("draft: \(draft),")
        writer.line("onDraftChange: (value: string): void => { this.onDraftChange(value); },")
        writer.line("focusRequest: \(focusRequest),")
        writer.line("onDraftCommit: (value: string): void => { this.\(onDraftCommit)(value); },")
        writer.line("onCommit: (): void => { \(onCommit) },")
        writer.depth -= 1
        writer.line("})")
    }

    private static func invalid(_ location: SourceLocation?, _ message: String) -> Diagnostic {
        Diagnostic(code: "RFINPUT002", message: message,
                   suggestion: "Use the bounded text-input host signature.", location: location)
    }
}
