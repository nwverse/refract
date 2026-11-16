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
                      let value = scalar(operationCall.arguments.first!.expression),
                      value.type == .string else {
                    error("RFNATIVE004", "`\(name)` requires one statically typed String value.",
                              "Use a literal, declared String input, or typed item/model String property", at: operationCall)
                    return nil
                }
                operation = name == "testTag" ? .testTag(value.expression) : .contentDescription(value.expression)
            case "retainCallback":
                guard operationCall.arguments.count == 1,
                      operationCall.arguments.first?.label?.text == "identity",
                      operationCall.trailingClosure == nil,
                      let identity = stringLiteral(operationCall.arguments.first!.expression),
                      !identity.isEmpty, identity.allSatisfy({
                          $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
                      }) else {
                    error("RFNATIVE004", "Retained callback identity requires one literal ASCII identifier.",
                              "Use `.retainCallback(identity: \"screen.action\")` on the action-owning view", at: operationCall)
                    return nil
                }
                guard case .button = node else {
                    error("RFNATIVE004", "Callback retention requires a typed action on the modified view.",
                              "Attach retention directly to a Button with a declared model action", at: operationCall)
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
        return .nativeModifier(child: node,
                               operations: zip(operations, locations).map {
                                   NativeModifier(operation: $0.0, location: $0.1)
                               }, location: location(of: call))
    }

    func accessibilityLabel(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil,
              let value = scalar(call.arguments.first!.expression), value.type == .string else {
            error("RFNATIVE004", "The iOS accessibilityLabel branch requires one typed String value.",
                      "Keep the real SwiftUI accessibility modifier in the explicit iOS branch", at: call)
            return nil
        }
        return modifier("accessibilityLabel", arguments: [value.expression], on: node, at: call)
    }
}
