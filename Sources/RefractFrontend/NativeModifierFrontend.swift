import RefractIR
import SwiftSyntax

extension Builder {
    func nativeModifier(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard !call.arguments.isEmpty, call.trailingClosure == nil,
              call.additionalTrailingClosures.isEmpty else {
            error("RFNATIVE004", "Native modifier interop requires a nonempty, closed list of typed operations.",
                  "Use `.refractNativeModifier(.testTag(\"...\"))` inside a platform view branch", at: call)
            return nil
        }
        switch node {
        case .nativeModifier, .forEach, .section, .listItem, .spacer, .platformView:
            error("RFNATIVE004", "This native modifier receiver cannot preserve the declared operation.",
                      "Apply the closed native operations to a concrete view or container", at: call)
            return nil
        default: break
        }
        var operations: [NativeModifier.Operation] = []
        var locations: [RefractIR.SourceLocation] = []
        for argument in call.arguments {
            guard argument.label == nil,
                  let operationCall = argument.expression.as(FunctionCallExprSyntax.self),
                  let member = operationCall.calledExpression.as(MemberAccessExprSyntax.self),
                  member.base == nil else {
                error("RFNATIVE004", "A native modifier must be a closed, unlabeled operation.",
                          "Use `.testTag`, `.contentDescription`, or `.retainCallback(identity:)`", at: argument)
                return nil
            }
            let name = member.declName.baseName.text
            let operation: NativeModifier.Operation
            switch name {
            case "testTag", "contentDescription":
                guard operationCall.arguments.count == 1, operationCall.arguments.first?.label == nil,
                      operationCall.trailingClosure == nil,
                      let value = measurementString(operationCall.arguments.first!.expression) else {
                    error("RFNATIVE004", "`\(name)` requires one statically typed String value or typed scalar interpolation.",
                              "Use a literal, declared item/model property, or interpolation of typed scalar values", at: operationCall)
                    return nil
                }
                operation = name == "testTag" ? .testTag(value.expression) : .contentDescription(value.expression)
            case "contentType":
                guard operationCall.arguments.count == 1, operationCall.arguments.first?.label == nil,
                      operationCall.trailingClosure == nil,
                      let identity = stringLiteral(operationCall.arguments.first!.expression),
                      identity.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }),
                      let first = identity.first, first.isLowercase else {
                    error("RFNATIVE004", "A row content type needs a stable lowercase ASCII identifier.",
                              "Use `.contentType(\"setting\")` on a generated child that is a direct dynamic List row", at: operationCall)
                    return nil
                }
                guard case let .child(child, _) = node, child.contentType == nil else {
                    error("RFNATIVE004", "A row content type applies once to a generated child View.",
                              "Put `.contentType(\"setting\")` directly on the generated child row", at: operationCall)
                    return nil
                }
                operation = .contentType(identity)
            case "retainCallback":
                guard operationCall.arguments.count == 1,
                      operationCall.arguments.first?.label?.text == "identity",
                      operationCall.trailingClosure == nil,
                      let identity = stringLiteral(operationCall.arguments.first!.expression),
                      !identity.isEmpty, identity.allSatisfy({
                          $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".")
                      }) else {
                    error("RFNATIVE004", "Retained callback identity requires one literal ASCII identifier.",
                              "Use `.retainCallback(identity: \"screen.action\")` on the action-owning view", at: operationCall)
                    return nil
                }
                switch node {
                case let .button(_, action?, _, _):
                    if case .modelMethod = action { break }
                    error("RFNATIVE004", "Callback retention requires a typed model action.",
                              "Attach retention to a Button with a declared model action", at: operationCall)
                    return nil
                case let .toggle(_, value, _, _, _, _):
                    guard case .valueProperty(.itemBinding) = value.value else {
                        error("RFNATIVE004", "Toggle callback retention requires a checked item model action.",
                                  "Use the typed current-item Binding with its stable stored id", at: operationCall)
                        return nil
                    }
                default:
                    error("RFNATIVE004", "Callback retention requires a typed action on the modified view.",
                              "Attach retention directly to a model-action Button or typed item Toggle", at: operationCall)
                    return nil
                }
                operation = .retainCallback(identity: identity)
            case "textSelection":
                guard let parsed = parseTextSelection(operationCall, on: node) else { return nil }
                operation = parsed
            case "dragPayload":
                guard let parsed = parseDragPayload(operationCall) else { return nil }
                operation = parsed
            case "dropTarget":
                guard let parsed = parseDropTarget(operationCall) else { return nil }
                operation = parsed
            default:
                error("RFNATIVE004", "Native modifier operation `\(name)` is not in the closed typed contract.",
                          "Use testTag, contentDescription, or retainCallback with the documented arguments", at: operationCall)
                return nil
            }
            operations.append(operation)
            locations.append(location(of: operationCall))
        }
        if case let .child(child, childLocation) = node {
            guard operations.count == 1, case let .contentType(identity) = operations[0] else {
                error("RFNATIVE004", "A generated child accepts only one explicit row content type.",
                      "Use `.refractNativeModifier(.contentType(\"setting\"))` on a direct dynamic List row", at: call)
                return nil
            }
            return .child(ChildView(name: child.name, arguments: child.arguments, models: child.models,
                                    item: child.item, contentType: identity), location: childLocation)
        }
        if case let .toggle(title, value, modifiers, nativeModifiers, labelsHidden, location) = node {
            return .toggle(title: title, value: value, modifiers: modifiers, nativeModifiers: nativeModifiers + zip(operations, locations).map {
                NativeModifier(operation: $0.0, location: $0.1)
            }, labelsHidden: labelsHidden, location: location)
        }
        return .nativeModifier(child: node,
                               operations: zip(operations, locations).map {
                                   NativeModifier(operation: $0.0, location: $0.1)
                               }, location: location(of: call))
    }

    // MARK: - Selection / drag / drop operations

    /// `.textSelection(start: <Int>, end: <Int>, action: "modelMethod")` on a TextField receiver.
    private func parseTextSelection(_ call: FunctionCallExprSyntax,
                                    on node: ViewNode) -> NativeModifier.Operation? {
        guard case .textInput = node else {
            error("RFNATIVE005", "Text selection editing applies only to a TextField.",
                  "Attach `.textSelection(start:end:action:)` directly to the TextField it edits", at: call)
            return nil
        }
        var start: TypedExpression?
        var end: TypedExpression?
        var action: String?
        for argument in call.arguments {
            switch argument.label?.text {
            case "start":
                start = modelTypedProperty(argument.expression) ?? scalar(argument.expression)
                if start?.type != .int {
                    error("RFNATIVE005", "Selection `start` must be a typed Int expression.",
                          "Use a literal, declared item/model property of type Int", at: argument)
                    return nil
                }
            case "end":
                end = modelTypedProperty(argument.expression) ?? scalar(argument.expression)
                if end?.type != .int {
                    error("RFNATIVE005", "Selection `end` must be a typed Int expression.",
                          "Use a literal, declared item/model property of type Int", at: argument)
                    return nil
                }
            case "action":
                guard let name = stringLiteral(argument.expression),
                      !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      let first = name.first, first.isLetter else {
                    error("RFNATIVE005", "Selection `action` must be a literal Swift identifier naming a model method.",
                          "Pass `action: \"replaceSelection\"` and declare `func replaceSelection(start: Int, end: Int, replacement: String)` on the model", at: argument)
                    return nil
                }
                action = name
            default:
                error("RFNATIVE005", "Unknown textSelection argument `\(argument.label?.text ?? "_")`.",
                      "Use `.textSelection(start: <Int>, end: <Int>, action: \"replaceSelection\")`", at: argument)
                return nil
            }
        }
        guard let start, let end, let action else {
            error("RFNATIVE005", "textSelection requires `start`, `end` and `action`.",
                  "Use `.textSelection(start: <Int>, end: <Int>, action: \"replaceSelection\")`", at: call)
            return nil
        }
        return .textSelection(start: start.expression, end: end.expression, action: action)
    }

    /// `.dragPayload(kind: "note", value: <String>)` on any concrete view.
    private func parseDragPayload(_ call: FunctionCallExprSyntax) -> NativeModifier.Operation? {
        var kind: String?
        var value: TypedExpression?
        for argument in call.arguments {
            switch argument.label?.text {
            case "kind":
                guard let name = stringLiteral(argument.expression), Self.isValidPayloadKind(name) else {
                    error("RFNATIVE005", "Drag payload `kind` must be a lowercase ASCII identifier.",
                          "Use `kind: \"note\"` with lowercase letters, digits and underscores, starting with a letter", at: argument)
                    return nil
                }
                kind = name
            case "value":
                guard let typed = modelTypedProperty(argument.expression) ?? scalar(argument.expression),
                      typed.type == .string else {
                    error("RFNATIVE005", "Drag payload `value` must be a typed String expression.",
                          "Use a String literal or a declared String state/model property; arbitrary URI/Any/clipboard reads are not supported", at: argument)
                    return nil
                }
                value = typed
            default:
                error("RFNATIVE005", "Unknown dragPayload argument `\(argument.label?.text ?? "_")`.",
                      "Use `.dragPayload(kind: \"note\", value: <String>)`", at: argument)
                return nil
            }
        }
        guard let kind, let value else {
            error("RFNATIVE005", "dragPayload requires `kind` and `value`.",
                  "Use `.dragPayload(kind: \"note\", value: <String>)`", at: call)
            return nil
        }
        return .dragPayload(kind: kind, value: value.expression)
    }

    /// `.dropTarget(kind: "note", action: "receiveDrop")` on any concrete view.
    private func parseDropTarget(_ call: FunctionCallExprSyntax) -> NativeModifier.Operation? {
        var kind: String?
        var action: String?
        for argument in call.arguments {
            switch argument.label?.text {
            case "kind":
                guard let name = stringLiteral(argument.expression), Self.isValidPayloadKind(name) else {
                    error("RFNATIVE005", "Drop target `kind` must be a lowercase ASCII identifier.",
                          "Use `kind: \"note\"` with lowercase letters, digits and underscores, starting with a letter", at: argument)
                    return nil
                }
                kind = name
            case "action":
                guard let name = stringLiteral(argument.expression),
                      !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      let first = name.first, first.isLetter else {
                    error("RFNATIVE005", "Drop target `action` must be a literal Swift identifier naming a model method.",
                          "Pass `action: \"receiveDrop\"` and declare `func receiveDrop(kind: String, payload: String)` on the model", at: argument)
                    return nil
                }
                action = name
            default:
                error("RFNATIVE005", "Unknown dropTarget argument `\(argument.label?.text ?? "_")`.",
                      "Use `.dropTarget(kind: \"note\", action: \"receiveDrop\")`", at: argument)
                return nil
            }
        }
        guard let kind, let action else {
            error("RFNATIVE005", "dropTarget requires `kind` and `action`.",
                  "Use `.dropTarget(kind: \"note\", action: \"receiveDrop\")`", at: call)
            return nil
        }
        return .dropTarget(kind: kind, action: action)
    }

    private static func isValidPayloadKind(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase, first.isASCII else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    private func measurementString(_ expression: ExprSyntax) -> TypedExpression? {
        let diagnosticCount = diagnostics.count
        defer { diagnostics.removeSubrange(diagnosticCount...) }
        if let value = modelTypedProperty(expression) {
            if value.type == .string { return value }
        } else if let value = scalar(expression), value.type == .string {
            return value
        }
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        var segments: [StringInterpolationSegment] = []
        for segment in literal.segments {
            switch segment {
            case let .stringSegment(text):
                segments.append(.literal(text.content.text))
            case let .expressionSegment(interpolation):
                guard interpolation.expressions.count == 1,
                      let argument = interpolation.expressions.first, argument.label == nil,
                      let value = modelTypedProperty(argument.expression) ?? measurementScalar(argument.expression),
                      value.type != nil else { return nil }
                segments.append(.expression(value.expression))
            }
        }
        return TypedExpression(Expression(.interpolatedString(segments), type: .string,
                                          location: location(of: expression)), .string)
    }

    private func measurementScalar(_ expression: ExprSyntax) -> TypedExpression? {
        let previousCount = diagnostics.count
        guard let value = scalar(expression), value.type != nil else {
            diagnostics.removeSubrange(previousCount...)
            return nil
        }
        return value
    }

    func accessibilityLabel(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil,
              let value = modelTypedProperty(call.arguments.first!.expression) ?? scalar(call.arguments.first!.expression), value.type == .string else {
            error("RFNATIVE004", "The iOS accessibilityLabel branch requires one typed String value.",
                      "Keep the real SwiftUI accessibility modifier in the explicit iOS branch", at: call)
            return nil
        }
        return modifier("accessibilityLabel", arguments: [value.expression], on: node, at: call)
    }
}
