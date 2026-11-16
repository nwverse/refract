/// A source coordinate. Frontend-independent consumers can report locations without SwiftSyntax.
public struct SourceLocation: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct Diagnostic: Codable, Error, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable { case error, warning }

    public let code: String
    public let severity: Severity
    public let message: String
    public let suggestion: String?
    public let location: SourceLocation?

    public init(code: String, severity: Severity = .error, message: String, suggestion: String? = nil,
                location: SourceLocation? = nil) {
        self.code = code
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.location = location
    }

    /// Stable, machine-readable text used by the CLI and golden files.
    public var rendered: String {
        let at = location.map { "\($0.file):\($0.line):\($0.column): " } ?? ""
        let fix = suggestion.map { " Suggestion: \($0)" } ?? ""
        return "\(at)error [\(code)]: \(message)\(fix)"
    }
}

public enum ValueType: String, Codable, Sendable {
    case string, bool, double, int
}

public struct Expression: Codable, Equatable, Sendable {
    public indirect enum Value: Codable, Equatable, Sendable {
        case stringLiteral(String)
        case stringKey(String)
        case boolLiteral(Bool)
        case numberLiteral(String)
        case layoutSpacing(LayoutSpacing)
        case reference(String)
        case binding(String)
        case valueProperty(ValueProperty)
        case interpolatedString([StringInterpolationSegment])
        case platformValue(PlatformAlternatives<Expression>)
    }

    public let value: Value
    public let location: SourceLocation?

    public init(_ value: Value, location: SourceLocation? = nil) {
        self.value = value
        self.location = location
    }
}

public struct Modifier: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [Expression]
    public let location: SourceLocation?

    public init(name: String, arguments: [Expression] = [], location: SourceLocation? = nil) {
        self.name = name
        self.arguments = arguments
        self.location = location
    }
}

public indirect enum ViewNode: Codable, Equatable, Sendable {
    case stack(axis: StackAxis, children: [ViewNode], modifiers: [Modifier], location: SourceLocation?)
    case text(Expression, modifiers: [Modifier], location: SourceLocation?)
    case button(label: ViewNode, action: StateAction?, modifiers: [Modifier], location: SourceLocation?)
    case native(NativeComponent, location: SourceLocation?)
    case platformView(PlatformAlternatives<[ViewNode]>, location: SourceLocation?)
    case conditional(conditions: [ConditionBranch], location: SourceLocation?)
    case layout(LayoutContainer, children: [ViewNode], modifiers: [Modifier], location: SourceLocation?)
    case scroll(axis: StackAxis, child: ViewNode, modifiers: [Modifier], location: SourceLocation?)
    case list(children: [ViewNode], modifiers: [Modifier], location: SourceLocation?)
    case section(header: Expression?, children: [ViewNode], location: SourceLocation?)
    case listItem(child: ViewNode, location: SourceLocation?)
    case forEach(ListItems, location: SourceLocation?)
    case image(source: ImageSource, modifiers: [Modifier], location: SourceLocation?)
    case toggle(title: Expression, value: Expression, modifiers: [Modifier], location: SourceLocation?)
    case textInput(placeholder: Expression?, value: Expression, modifiers: [Modifier], location: SourceLocation?)
    case label(title: Expression, image: ImageSource, modifiers: [Modifier], location: SourceLocation?)
    case divider(modifiers: [Modifier], location: SourceLocation?)
    case spacer(location: SourceLocation?)

    public enum StackAxis: String, Codable, Sendable { case vertical, horizontal, depth }

    public struct ConditionBranch: Codable, Equatable, Sendable {
        public let condition: Expression?
        public let children: [ViewNode]
        public init(condition: Expression?, children: [ViewNode]) {
            self.condition = condition
            self.children = children
        }
    }
}

public enum StateDeclaration: Codable, Equatable, Sendable {
    case state(name: String, type: ValueType, initialValue: Expression?, location: SourceLocation?)
    case binding(name: String, type: ValueType, location: SourceLocation?)
    case model(ModelReference, location: SourceLocation?)
}

public struct ModelReference: Codable, Equatable, Sendable {
    public let propertyName: String
    public let protocolName: String
    public init(propertyName: String, protocolName: String) {
        self.propertyName = propertyName
        self.protocolName = protocolName
    }
}

public struct NativeComponent: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [NativeArgument]
    public init(name: String, arguments: [NativeArgument] = []) {
        self.name = name
        self.arguments = arguments
    }
}

public struct Screen: Codable, Equatable, Sendable {
    public let name: String
    public let states: [StateDeclaration]
    public let body: ViewNode
    public let location: SourceLocation?

    public init(name: String, states: [StateDeclaration] = [], body: ViewNode, location: SourceLocation? = nil) {
        self.name = name
        self.states = states
        self.body = body
        self.location = location
    }
}

public struct Module: Codable, Equatable, Sendable {
    public let sourceFile: String
    public let screens: [Screen]
    public let nativeDeclarations: [NativeDeclaration]
    public let models: [ModelProtocol]
    public init(sourceFile: String, screens: [Screen], nativeDeclarations: [NativeDeclaration] = [],
                models: [ModelProtocol] = []) {
        self.sourceFile = sourceFile
        self.screens = screens
        self.nativeDeclarations = nativeDeclarations
        self.models = models
    }
}

public struct TranslationUnit: Codable, Equatable, Sendable {
    public let module: Module
    public let diagnostics: [Diagnostic]
    public init(module: Module, diagnostics: [Diagnostic] = []) {
        self.module = module
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

public struct SourceFile: Equatable, Sendable {
    public let path: String
    public let contents: String
    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}

