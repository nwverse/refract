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
