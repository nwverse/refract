import RefractIR
import SwiftSyntax

struct InteropFrontend {
    let file: String
    let converter: SourceLocationConverter
    var declarations: [NativeDeclaration] = []
    var locations: [String: RefractIR.SourceLocation] = [:]
    var diagnostics: [Diagnostic] = []
    private var names: Set<String> = []
    var invalidDeclarations: Set<String> = []

    mutating func takeDiagnostics() -> [Diagnostic] {
        defer { diagnostics.removeAll() }
        return diagnostics
    }

    mutating func declaration(_ node: StructDeclSyntax) -> Bool {
        let inherited = node.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        if inherited.contains("RefractTextInputHost") {
            return textInputHostDeclaration(node, inherited: inherited)
        }
        guard inherited.contains("RefractNativeView") else { return false }
        guard inherited == ["RefractNativeView"] else {
            diagnostics.append(error("RFNATIVE001", "Native component `\(node.name.text)` must inherit only `RefractNativeView`.",                  "Keep the marker view's other behavior inside its ordinary SwiftUI body", at: node.name))
            return true
        }
        guard names.insert(node.name.text).inserted else {
            invalidDeclarations.insert(node.name.text)
            diagnostics.append(error("RFNATIVE001", "Native component `\(node.name.text)` is declared more than once.",
                  "Give each native view one unique declaration", at: node.name))
            return true
        }
        var parameters: [NativeParameter] = []
        for member in node.memberBlock.members {
            guard let property = member.decl.as(VariableDeclSyntax.self) else {
                diagnostics.append(error("RFNATIVE001", "Native component `\(node.name.text)` contains an unsupported declaration.",
                      "Use typed immutable stored properties and a computed SwiftUI `body`", at: member))
                continue
            }
            for binding in property.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      pattern.identifier.text != "body" else { continue }
                // Accessibility configuration belongs to the ordinary iOS body, not the cross-platform ABI.
                // Other property wrappers remain diagnostics rather than silently widening that ABI.
                if Self.isReduceMotionEnvironment(property, binding) { continue }
                guard property.bindingSpecifier.tokenKind == .keyword(.let),
                      binding.initializer == nil, binding.accessorBlock == nil,
                      let annotation = binding.typeAnnotation,
                      let type = Self.scalarType(annotation.type.trimmedDescription) else {
                    diagnostics.append(error("RFNATIVE001", "Native component `\(node.name.text)` has an unsupported stored property.",
"Use `let` with an explicit supported scalar, Image, LocalizedStringKey, RawAsset, RemoteImageLoader or `() -> Void` type", at: binding))
                    invalidDeclarations.insert(node.name.text)
                    continue
                }
                parameters.append(NativeParameter(label: pattern.identifier.text, type: type,
                                                  location: location(of: binding)))
            }
        }
        declarations.append(NativeDeclaration(name: node.name.text, parameters: parameters,
                                              location: location(of: node.name)))
        locations[node.name.text] = location(of: node.name)
        return true
    }

    mutating func textInputHostDeclaration(_ node: StructDeclSyntax, inherited: [String]) -> Bool {
        let name = node.name.text
        let host = TextInputHostFrontend(file: file, converter: converter)
        let result = host.validate(node, inherited: inherited)
        diagnostics.append(contentsOf: result.diagnostics)
        guard result.isValid else {
            invalidDeclarations.insert(name)
            if result.diagnostics.isEmpty {
                diagnostics.append(error("RFINPUT001",
                    "The text-input host must declare its complete signature and private native focus state.",
                    "Use draft, focusRequest, typed callbacks, @FocusState and an ordinary SwiftUI body", at: node.name))
            }
            return true
        }
        declarations.append(NativeDeclaration(name: name, parameters: result.parameters,
                                              kind: .textInputHost, location: location(of: node.name)))
        locations[name] = location(of: node.name)
        return true
    }

    func validate(_ component: NativeComponent, declaration: NativeDeclaration?,
                  location: RefractIR.SourceLocation?) -> [Diagnostic] {
        guard let declaration else {
            return [diagnostic("RFNATIVE001",
                "View `\(component.name)` is neither in the supported subset nor declared as a `RefractNativeView`.",
                "Declare `\(component.name): RefractNativeView` with typed stored properties and an iOS SwiftUI body",
                at: location)]
        }
        guard component.arguments.count == declaration.parameters.count else {
            return [diagnostic("RFNATIVE002",
                "Native component `\(component.name)` expects \(declaration.parameters.count) arguments but receives \(component.arguments.count).",
                "Use the memberwise initializer `\(Self.signature(declaration.parameters))`", at: location)]
        }
        var diagnostics: [Diagnostic] = []
        for (argument, parameter) in zip(component.arguments, declaration.parameters) {
            guard argument.label == parameter.label else {
                diagnostics.append(diagnostic("RFNATIVE002",
                    "Native component `\(component.name)` expects `\(parameter.label)` in this position, not `\(argument.label)`.",
                    "Use declaration-order labels `\(Self.signature(declaration.parameters))`", at: argument.location))
                continue
            }
            let actualType = argument.type
            guard let actualType else {
                diagnostics.append(diagnostic("RFSEM001",
                    "Native component `\(component.name)` cannot infer the type of `\(argument.label)`.",
                    "Use a literal or a typed state/model property supported by the state frontend", at: argument.location))
                continue
            }
            let expectedCallback = declaration.kind == .textInputHost
                ? ["onDraftCommit": NativeParameterType.actionString, "onCommit": .action][parameter.label] : nil
            let expectedParameterType = expectedCallback ?? parameter.type
            guard actualType == expectedParameterType else {
                diagnostics.append(diagnostic("RFNATIVE002",
                    "Native component `\(component.name)` expects `\(parameter.label): \(parameter.type.rawValue)` but receives \(actualType.rawValue).",
                    "Pass a value of the declared Swift type", at: argument.location))
                continue
            }
        }
        return diagnostics
    }

    static func scalarType(_ type: String) -> NativeParameterType? {
        switch type {
        case "String", "string": .string
        case "Bool", "bool": .bool
        case "Int", "int": .int
        case "Double", "double": .double
        case "Image": .image
        case "LocalizedStringKey": .stringKey
        case "RemoteImageLoader": .remoteImageLoader
        case "RawAsset": .rawAsset
        case "() -> Void": .action
        case "(String) -> Void": .actionString
        case "RefractSelectionContent": .selectionContent
        case "(RefractSelectionContext) -> Void": .selectionContextAction
        default: nil
        }
    }

    static func isReduceMotionEnvironment(_ property: VariableDeclSyntax,
                                          _ binding: PatternBindingSyntax) -> Bool {
        property.bindingSpecifier.tokenKind == .keyword(.var)
            && binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "reduceMotion"
            && binding.accessorBlock == nil
            && property.attributes.trimmedDescription == "@Environment(\\.accessibilityReduceMotion)"
    }

    static func signature(_ parameters: [NativeParameter]) -> String {
        parameters.map { "\($0.label): \($0.type.sourceName)" }.joined(separator: ", ")
    }

    func error(_ code: String, _ message: String, _ suggestion: String,
               at node: some SyntaxProtocol) -> Diagnostic {
        diagnostic(code, message, suggestion, at: location(of: node))
    }

    func diagnostic(_ code: String, _ message: String, _ suggestion: String,
                    at location: RefractIR.SourceLocation?) -> Diagnostic {
        Diagnostic(code: code, message: message, suggestion: suggestion, location: location)
    }

    func location(of node: some SyntaxProtocol) -> RefractIR.SourceLocation {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RefractIR.SourceLocation(file: file, line: position.line, column: position.column)
    }
}
