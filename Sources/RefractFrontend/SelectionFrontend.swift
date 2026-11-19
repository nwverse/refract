import Foundation
import RefractIR
import SwiftSyntax

extension Builder {
    func nativeStringAction(_ expression: ExprSyntax, label: String) -> NativeArgument? {
        guard let closure = expression.as(ClosureExprSyntax.self),
              let parameter = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameter.count == 1, parameter.first?.name.text == "destination",
              closure.signature?.capture == nil,
              closure.signature?.returnClause.map({ $0.type.trimmedDescription == "Void" }) != false,
              closure.signature?.attributes.isEmpty != false, closure.signature?.effectSpecifiers == nil,
              closure.statements.count == 1,
              let body = closure.statements.first?.item.as(ExprSyntax.self),
              let action = modelAction(body) else {
            error("RFSELECTION005", "Link activation must invoke one declared `RefractModel` method with its destination.",
                  "Use `{ destination in model.openLink(destination) }`; no URL opening is generated", at: expression)
            return nil
        }
        guard case let .modelMethod(_, _, arguments) = action,
              arguments.count == 1, arguments[0].label == nil,
              arguments[0].value.value == .stringLiteral("__refract_destination") else {
            error("RFSELECTION006", "Link activation must forward the native destination unchanged.",
                  "Use `{ destination in model.openLink(destination) }` with a declared `String` model parameter", at: expression)
            return nil
        }
        return NativeArgument(label: label, action: action, type: .actionString,
                              location: location(of: expression))
    }

    func nativeSelectionContent(_ expression: ExprSyntax, label: String) -> NativeArgument? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "RefractSelectionContent",
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("RFSELECTION001", "Selection content must be a closed literal `RefractSelectionContent` value.",
                  "Use literal text and static UTF-16 link ranges; projected messages need a separate typed adapter", at: expression)
            return nil
        }
        var text: String?
        var links: [SelectionLink] = []
        for argument in call.arguments {
            switch argument.label?.text {
            case "text":
                text = stringLiteral(argument.expression)
            case "links":
                guard let elements = argument.expression.as(ArrayExprSyntax.self)?.elements else {
                    error("RFSELECTION001", "Selection links must be a static array of `RefractSelectionLink` values.",
                          "Use nonempty, disjoint, scalar-aligned UTF-16 ranges with literal HTTPS destinations", at: argument)
                    return nil
                }
                for element in elements {
                    guard let link = selectionLink(element.expression, text: text) else { return nil }
                    links.append(link)
                }
            default:
                error("RFSELECTION001", "Unknown selection-content argument.",
                      "Use `RefractSelectionContent(text: ..., links: ...)` with literal values", at: argument)
                return nil
            }
        }
        guard let text else {
            error("RFSELECTION001", "Selection content requires one literal `text` value.",
                  "Do not pass a dynamically projected message as literal selection content", at: expression)
            return nil
        }
        var previousEnd = 0
        for link in links {
            guard link.range.start >= previousEnd else {
                error("RFSELECTION002", "Selection link ranges must be disjoint and ordered.",
                      "Use nonoverlapping ranges in increasing UTF-16 order", at: expression)
                return nil
            }
            previousEnd = link.range.end
        }
        return NativeArgument(label: label, selection: SelectionContent(text: text, links: links),
                              type: .selectionContent, location: location(of: expression))
    }

    private func selectionLink(_ expression: ExprSyntax, text: String?) -> SelectionLink? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "RefractSelectionLink",
              call.arguments.count == 2, call.arguments.first?.label?.text == "range",
              call.arguments.last?.label?.text == "destination",
              let rangeCall = call.arguments.first?.expression.as(FunctionCallExprSyntax.self),
              rangeCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "RefractSelectionRange",
              rangeCall.arguments.count == 2, rangeCall.arguments.first?.label?.text == "start",
              rangeCall.arguments.last?.label?.text == "end",
              let start = integerLiteral(rangeCall.arguments.first!.expression),
              let end = integerLiteral(rangeCall.arguments.last!.expression),
              let destination = stringLiteral(call.arguments.last!.expression) else {
            error("RFSELECTION002", "A selection link requires static `range` and `destination` values.",
                  "Use `RefractSelectionLink(range: RefractSelectionRange(start: ..., end: ...), destination: \"https://...\")`", at: expression)
            return nil
        }
        guard let text else {
            error("RFSELECTION002", "Declare selection `text` before its links so UTF-16 bounds can be checked.",
                  "Put the literal `text` argument before `links`", at: expression)
            return nil
        }
        guard start >= 0, start < end, end <= text.utf16.count,
              isScalarBoundary(start, in: text), isScalarBoundary(end, in: text) else {
            error("RFSELECTION003", "A link range must be nonempty, in bounds and aligned to Unicode scalar boundaries.",
                  "Use static UTF-16 offsets; do not split an emoji surrogate pair", at: expression)
            return nil
        }
        guard isSelectionHTTPS(destination) else {
            error("RFSELECTION004", "Selection links require a literal absolute HTTPS destination.",
                  "Use `https://` with a non-empty host; dynamic URLs and other schemes are unsupported", at: expression)
            return nil
        }
        return SelectionLink(range: SelectionRange(start: start, end: end), destination: destination)
    }

    func selectionContextArgument(_ expression: ExprSyntax, expected: ValueType) -> RefractIR.Expression? {
        if expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "destination",
           expected == .string {
            return RefractIR.Expression(.stringLiteral("__refract_destination"), type: .string,
                              location: location(of: expression))
        }
        guard (expression.as(MemberAccessExprSyntax.self)?.trimmedDescription.hasPrefix("context.")) == true else {
            return nil
        }
        return RefractIR.Expression(.reference(expression.trimmedDescription), type: expected,
                          location: location(of: expression))
    }

    private func integerLiteral(_ expression: ExprSyntax) -> Int? {
        guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
        return Int(literal.literal.text)
    }

    private func isScalarBoundary(_ offset: Int, in text: String) -> Bool {
        let units = Array(text.utf16)
        guard offset > 0, offset < units.count else { return true }
        let before = units[offset - 1]
        let after = units[offset]
        return !((0xD800...0xDBFF).contains(before) && (0xDC00...0xDFFF).contains(after))
    }

    private func isSelectionHTTPS(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }

    func nativeSelectionContextAction(_ expression: ExprSyntax, label: String) -> NativeArgument? {
        guard let closure = expression.as(ClosureExprSyntax.self),
              let parameter = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameter.count == 1, parameter.first?.name.text == "context",
              closure.signature?.capture == nil,
              closure.signature?.returnClause.map({ $0.type.trimmedDescription == "Void" }) != false,
              closure.signature?.attributes.isEmpty != false, closure.signature?.effectSpecifiers == nil,
              closure.statements.count == 1,
              let body = closure.statements.first?.item.as(ExprSyntax.self),
              let action = modelAction(body) else {
            error("RFSELECTION005", "A context callback must invoke one declared `RefractModel` method with the supplied context.",
                  "Use `{ context in model.useAsContext(start: context.range.start, end: context.range.end, text: context.text) }`", at: expression)
            return nil
        }
        guard case let .modelMethod(modelName, name, arguments) = action,
              arguments.map(\.label) == ["start", "end", "text"],
              arguments.map(\.value.value) == [
                .reference("context.range.start"), .reference("context.range.end"), .reference("context.text"),
              ],
              let reference = currentModels.first(where: { $0.propertyName == modelName }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let method = contract.actions.first(where: { $0.name == name }),
              method.effect == nil,
              method.parameters.map(\.type) == [.int, .int, .string],
              method.parameters.map(\.externalName) == ["start", "end", "text"] else {
            error("RFSELECTION006", "A context callback must forward the complete snapshot to a declared model method.",
                  "Declare `func useAsContext(start: Int, end: Int, text: String)` and forward `context.range` and `context.text` unchanged", at: expression)
            return nil
        }
        return NativeArgument(label: label, action: action, type: .selectionContextAction,
                              location: location(of: expression))
    }
}
