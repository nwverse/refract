import Foundation

/// A common target binding, independent of how refract.json is decoded. The mapping loader normalizes its
/// component registry into these records before native interop validation.
public struct NativeTarget: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case composable, component }
    public enum ArgumentStyle: String, Codable, Sendable { case named, object, positional }

    public struct Parameter: Codable, Equatable, Sendable {
        public let label: String
        public let type: NativeParameterType
        public let required: Bool
        /// Explicit target type for compatibility declarations; canonical mappings use the source NativeParameterType.
        public let targetType: String?
        public init(label: String, type: NativeParameterType, required: Bool = true, targetType: String? = nil) {
            self.label = label
            self.type = type
            self.required = required
            self.targetType = targetType
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
    public static func validate(declaration: NativeDeclaration, target: NativeTarget?, platform: TargetPlatform,
                                location: SourceLocation? = nil) throws -> NativeTarget {
        let name = platform == .android ? "Android" : "HarmonyOS"
        guard let target else {
            throw InteropMappingError(diagnostics: [Diagnostic(code: "RFMAP002",
                message: "Native component `\(declaration.name)` has no \(name) mapping.",
                suggestion: "Declare a typed implementation with ordered parameters `\(signature(declaration.parameters))`.",
                location: location ?? declaration.location)])
        }
        let diagnostics = validateHost(declaration, platform: name, location: location)
            + validate(target: target, declaration: declaration, platform: name, location: location)
        guard diagnostics.isEmpty else { throw InteropMappingError(diagnostics: diagnostics) }
        return target
    }

    private static let textInputHostParameters: [(String, NativeParameterType)] = [
        ("draft", .string), ("focusRequest", .int), ("onDraftCommit", .string), ("onCommit", .string),
    ]

    private static func validateHost(_ declaration: NativeDeclaration, platform: String,
                                     location: SourceLocation?) -> [Diagnostic] {
        let expected = declaration.kind == .textInputHost ? textInputHostParameters : []
        let valid = declaration.kind == .textInputHost
            ? declaration.name == "NativeTextInputHost"
                && declaration.parameters.map { ($0.label, $0.type) }.elementsEqual(expected, by: ==)
            : declaration.parameters.allSatisfy { parameter in
                parameter.type != .actionString || parameter.label == "onLink"
            }
        return valid ? [] : [Diagnostic(code: "RFINPUT003",
            message: "Native component `\(declaration.name)` does not have a valid \(platform) text-input host ABI.",
            suggestion: declaration.kind == .textInputHost
                ? "Use draft: String, focusRequest: Int, onDraftCommit: (String) -> Void, onCommit: () -> Void."
                : "Use the dedicated RefractTextInputHost marker for bounded text-input callbacks.",
            location: location ?? declaration.location)]
    }

    /// Check both platforms together for declarations that have no call site.
    public static func validate(declaration: NativeDeclaration, android: NativeTarget?, harmonyOS: NativeTarget?,
                                location: SourceLocation? = nil) throws -> (android: NativeTarget, harmonyOS: NativeTarget) {
        var diagnostics: [Diagnostic] = []
        for (platform, target) in [(TargetPlatform.android, android), (TargetPlatform.harmonyOS, harmonyOS)] {
            do { _ = try validate(declaration: declaration, target: target, platform: platform, location: location) }
            catch let error as InteropMappingError { diagnostics.append(contentsOf: error.diagnostics) }
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
                let expectedTargetType = targetType(expected.type, platform: platform)
                let expectedType: NativeParameterType = if declaration.kind == .textInputHost {
                    switch expected.label {
                    case "onDraftCommit": .actionString
                    case "onCommit": .action
                    default: expected.type
                    }
                } else {
                    expected.type
                }
                let actualTargetType = actual.targetType ?? actual.type.rawValue
                let typesMatch = actual.targetType != nil || actual.type == expectedType
                if actual.label != expected.label || !typesMatch || !actual.required {
                    diagnostics.append(Diagnostic(code: "RFMAP003",
                        message: "Native component `\(declaration.name)` expects Swift `\(expected.label): \(expected.type.rawValue)`, required; \(platform) mapping declares `\(actual.label): \(actualTargetType)`, required: \(actual.required).",
                        suggestion: "Match the stored-property signature in declaration order.",
                        location: location ?? declaration.location))
                } else if actual.targetType != nil && actual.targetType != expectedTargetType {
                    diagnostics.append(Diagnostic(code: "RFMAP003",
                        message: "Native component `\(declaration.name)` maps Swift `\(expected.label): \(expected.type.rawValue)` to \(platform) `\(actualTargetType)`; expected `\(expectedTargetType)`.",
                        suggestion: "Use the declared target type for this source scalar.",
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

    private static func targetType(_ type: NativeParameterType, platform: String) -> String {
        if platform == "HarmonyOS" {
            return switch type {
            case .string, .stringKey: "string"
            case .bool: "boolean"
            case .int, .double, .image: "number"
            case .remoteImageLoader: "RemoteImageLoader"
            case .action: "() => void"
            case .actionString: "(string) => void"
            case .selectionContent: "RefractSelectionContent"
            case .selectionContextAction: "(context: RefractSelectionContext) => void"
            }
        }
        return switch type {
        case .string, .stringKey: "String"
        case .bool: "Boolean"
        case .int, .image: "Int"
        case .double: "Double"
        case .remoteImageLoader: "RemoteImageLoader"
        case .action: "() -> Unit"
        case .actionString: "(String) -> Unit"
        case .selectionContent: "RefractSelectionContent"
        case .selectionContextAction: "(RefractSelectionContext) -> Unit"
        }
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
