import Foundation

/// A common target binding, independent of how refract.json is decoded. The mapping loader normalizes its
/// component registry into these records before native interop validation.
public struct NativeTarget: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case composable, component }
    public enum ArgumentStyle: String, Codable, Sendable { case named, object, positional }

    public struct Parameter: Codable, Equatable, Sendable {
        public let label: String
        public let type: ValueType
        public let required: Bool
        public init(label: String, type: ValueType, required: Bool = true) {
            self.label = label
            self.type = type
            self.required = required
        }
    }

    public struct Argument: Codable, Equatable, Sendable {
        public let source: String
        public let target: String?
        public init(source: String, target: String?) {
            self.source = source
            self.target = target
        }
    }

    public let symbol: String
    public let module: String
    public let kind: Kind
    public let argumentStyle: ArgumentStyle
    public let parameters: [Parameter]
    public let arguments: [Argument]

    public init(symbol: String, module: String, kind: Kind, argumentStyle: ArgumentStyle,
                parameters: [Parameter], arguments: [Argument]) {
        self.symbol = symbol
        self.module = module
        self.kind = kind
        self.argumentStyle = argumentStyle
        self.parameters = parameters
        self.arguments = arguments
    }
}

public enum InteropMapping {
    /// Check the source-owned signature before emitting either target. JSON parsing alone cannot establish this.
    public static func validate(declaration: NativeDeclaration, android: NativeTarget?, harmonyOS: NativeTarget?,
                                location: SourceLocation? = nil) throws -> (android: NativeTarget, harmonyOS: NativeTarget) {
        var diagnostics: [Diagnostic] = []
        for (platform, target) in [("Android", android), ("HarmonyOS", harmonyOS)] {
            guard let target else {
                diagnostics.append(Diagnostic(code: "RFMAP002",
                    message: "Native component `\(declaration.name)` has no \(platform) mapping.",
                    suggestion: "Declare a typed implementation with ordered parameters `\(signature(declaration.parameters))`.",
                    location: location ?? declaration.location))
                continue
            }
            diagnostics.append(contentsOf: validate(target: target, declaration: declaration,
                                                   platform: platform, location: location))
        }
        guard diagnostics.isEmpty, let android, let harmonyOS else {
            throw InteropMappingError(diagnostics: diagnostics)
        }
        return (android, harmonyOS)
    }

    private static func validate(target: NativeTarget, declaration: NativeDeclaration,
                                 platform: String, location: SourceLocation?) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if !target.symbol.allSatisfy(isIdentifier) {
            diagnostics.append(Diagnostic(code: "RFMAP003",
                message: "Native component `\(declaration.name)` has an invalid \(platform) symbol `\(target.symbol)`.",
                suggestion: "Use an unqualified target-language identifier.", location: location ?? declaration.location))
        }
        let expectedKind: NativeTarget.Kind = platform == "Android" ? .composable : .component
        if target.kind != expectedKind {
            diagnostics.append(Diagnostic(code: "RFMAP003",
                message: "Native component `\(declaration.name)` must map to a \(platform) \(expectedKind.rawValue).",
                suggestion: "Use the platform's direct native component kind.", location: location ?? declaration.location))
        }
        let expectedStyle: NativeTarget.ArgumentStyle = platform == "Android" ? .named : .object
        if target.argumentStyle != expectedStyle {
            diagnostics.append(Diagnostic(code: "RFMAP003",
                message: "Native component `\(declaration.name)` must use \(expectedStyle.rawValue) arguments on \(platform).",
                suggestion: "Use direct \(expectedStyle == .named ? "named" : "object-literal") arguments.",
                location: location ?? declaration.location))
        }
        if target.parameters.count != declaration.parameters.count {
            diagnostics.append(Diagnostic(code: "RFMAP003",
                message: "Native component `\(declaration.name)` declares \(target.parameters.count) \(platform) parameters; expected \(declaration.parameters.count).",
                suggestion: "Match `\(signature(declaration.parameters))` exactly.", location: location ?? declaration.location))
        } else {
            for (actual, expected) in zip(target.parameters, declaration.parameters) {
                if actual.label != expected.label || actual.type != expected.type || !actual.required {
                    diagnostics.append(Diagnostic(code: "RFMAP003",
                        message: "Native component `\(declaration.name)` expects \(platform) `\(expected.label): \(expected.type.rawValue)`, required; mapping declares `\(actual.label): \(actual.type.rawValue)`, required: \(actual.required).",
                        suggestion: "Match the stored-property signature in declaration order.",
                        location: location ?? declaration.location))
                }
            }
        }
        if target.arguments.count != declaration.parameters.count {
            diagnostics.append(Diagnostic(code: "RFMAP003",
                message: "Native component `\(declaration.name)` has \(target.arguments.count) \(platform) argument bindings; expected \(declaration.parameters.count).",
                suggestion: "Bind every required source argument exactly once.", location: location ?? declaration.location))
        } else {
            for (binding, parameter) in zip(target.arguments, declaration.parameters) {
                guard binding.source == parameter.label else {
                    diagnostics.append(Diagnostic(code: "RFMAP003",
                        message: "Native component `\(declaration.name)` binds `\(binding.source)` where `\(parameter.label)` is required on \(platform).",
                        suggestion: "Keep bindings in the source declaration order.", location: location ?? declaration.location))
                    continue
                }
                if binding.target?.allSatisfy(isIdentifier) != true {
                    diagnostics.append(Diagnostic(code: "RFMAP003",
                        message: "Native component `\(declaration.name)` has an invalid \(platform) target label for `\(parameter.label)`.",
                        suggestion: "Use an explicit valid target argument identifier.", location: location ?? declaration.location))
                }
            }
        }
        return diagnostics
    }

    private static func signature(_ parameters: [NativeParameter]) -> String {
        parameters.map { "\($0.label): \($0.type.rawValue)" }.joined(separator: ", ")
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character == "_" || character.isASCII && (character.isLetter || character.isNumber)
    }
}

public struct InteropMappingError: Error, Equatable, Sendable {
    public let diagnostics: [Diagnostic]
    public init(diagnostics: [Diagnostic]) { self.diagnostics = diagnostics }
}
