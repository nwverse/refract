import RefractIR
import SwiftSyntax

/// The bounded `refractForm` source contract. Field declarations and their rules are checked here
/// and lowered to native state and comparisons; no Swift validation body is ever translated.
extension Builder {
    var currentForms: [FormDeclaration] {
        currentStates.compactMap {
            guard case let .form(_, declaration, _) = $0 else { return nil }
            return declaration
        }
    }

    func form(named name: String) -> FormDeclaration? {
        currentForms.first { $0.name == name }
    }

    func formFieldReference(_ expression: ExprSyntax) -> TypedExpression? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self) else { return nil }
        if base.baseName.text.hasPrefix("$") {
            let formName = String(base.baseName.text.dropFirst())
            guard form(named: formName) != nil else { return nil }
            error("RFFORM005",
                  "The projected form value `$\(formName)` is not a control binding; project one field instead.",
                  "Use `TextField(\"key\", text: $\(formName).\(member.declName.baseName.text))`", at: expression)
            return nil
        }
        guard let declaration = form(named: base.baseName.text) else { return nil }
        let name = member.declName.baseName.text
        guard let field = declaration.field(named: name) else {
            error("RFFORM002", "Form `\(declaration.name)` has no declared field `\(name)`.",
                  "Declare the field inside `refractForm` or use a declared scalar property", at: member)
            return nil
        }
        return TypedExpression(Expression(.formField(form: declaration.name, field: name), type: field.type,
                                         location: location(of: expression)), field.type)
    }

    /// `Field("email", initial: "", rules: .nonEmpty)` inside a `refractForm` trailing closure.
    func formDeclaration(named name: String, initializer: ExprSyntax, at declaration: some SyntaxProtocol) -> FormDeclaration? {
        guard let call = initializer.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractForm",
              call.arguments.isEmpty, call.additionalTrailingClosures.isEmpty,
              let closure = call.trailingClosure else {
            error("RFFORM001", "A form declaration must be `refractForm { Field(...) ... }` with no arguments.",
                  "Declare `let form = refractForm { ... }` in the view's member list", at: declaration)
            return nil
        }
        guard !closure.statements.isEmpty else {
            error("RFFORM001", "Form `\(name)` declares no fields.",
                  "Declare at least one `Field(\"name\", initial: ...)`", at: closure)
            return nil
        }
        var fields: [FormField] = []
        for statement in closure.statements {
            guard let expression = statement.item.as(ExprSyntax.self),
                  let field = formFieldDeclaration(expression, form: name) else { return nil }
            if fields.contains(where: { $0.name == field.name }) {
                error("RFFORM001", "Form `\(name)` declares field `\(field.name)` more than once.",
                      "Give every field a unique name", at: expression)
                return nil
            }
            fields.append(field)
        }
        return FormDeclaration(name: name, fields: fields, location: location(of: declaration))
    }

    private func formFieldDeclaration(_ expression: ExprSyntax, form: String) -> FormField? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Field",
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let first = call.arguments.first, first.label == nil,
              let name = stringLiteral(first.expression),
              !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              name.first?.isLetter == true else {
            error("RFFORM001", "A form field must be `Field(\"fieldName\", initial: value)` with a Swift identifier name.",
                  "Use a quoted identifier as the field name", at: expression)
            return nil
        }
        for state in currentStates {
            let collides: Bool
            switch state {
            case let .state(other, _, _, _), let .binding(other, _, _): collides = other == name
            case let .navigationPath(other, _, _): collides = other == name
            case let .model(reference, _): collides = reference.propertyName == name
            case let .form(_, other, _): collides = other.name == name
            }
            if collides {
                error("RFFORM001", "Form field `\(name)` collides with another declared property of this view.",
                      "Give the field a unique Swift identifier", at: expression)
                return nil
            }
        }
        var initial: Expression?
        var rules: [FormField.Rule] = []
        var type: ValueType = .string
        for argument in call.arguments.dropFirst() {
            switch argument.label?.text {
            case "initial":
                guard initial == nil, let value = literal(argument.expression, expected: .string) else {
                    error("RFFORM001", "Field `\(name)` needs one String literal `initial:` value.",
                          "Use `initial: \"\"`; other field types are not part of this slice", at: argument)
                    return nil
                }
                initial = value
            case "rules":
                guard let parsed = formRules(argument.expression, field: name) else { return nil }
                rules.append(contentsOf: parsed)
            case "type":
                guard let member = argument.expression.as(MemberAccessExprSyntax.self),
                      member.declName.baseName.text == "string", type == .string else {
                    error("RFFORM001", "Only String form fields are supported in this slice.",
                          "Omit `type:` or use `type: .string`", at: argument)
                    return nil
                }
            default:
                error("RFFORM001", "Unsupported form field argument `\(argument.label?.text ?? "_")`.",
                      "Use `initial:` and `rules:` only", at: argument)
                return nil
            }
        }
        guard let initial else {
            error("RFFORM001", "Field `\(name)` has no `initial:` value.",
                  "Use `initial: \"\"` so the native draft starts from a known value", at: expression)
            return nil
        }
        return FormField(name: name, type: type, initialValue: initial, rules: rules,
                         location: location(of: expression))
    }

    private func formRules(_ expression: ExprSyntax, field: String) -> [FormField.Rule]? {
        if let array = expression.as(ArrayExprSyntax.self) {
            var rules: [FormField.Rule] = []
            for element in array.elements {
                guard let rule = formRule(element.expression, field: field) else { return nil }
                rules.append(rule)
            }
            return rules
        }
        guard let rule = formRule(expression, field: field) else { return nil }
        return [rule]
    }

    private func formRule(_ expression: ExprSyntax, field: String) -> FormField.Rule? {
        // `.equals("confirmation")` parses as a call whose callee is `.equals` with no arguments;
        // the string literal is the call's own argument. `.nonEmpty` is a bare member access.
        let member: MemberAccessExprSyntax?
        let call: FunctionCallExprSyntax?
        if let direct = expression.as(MemberAccessExprSyntax.self) {
            member = direct
            call = nil
        } else if let invocation = expression.as(FunctionCallExprSyntax.self) {
            member = invocation.calledExpression.as(MemberAccessExprSyntax.self)
            call = invocation
        } else {
            member = nil
            call = nil
        }
        guard let member, member.base == nil else {
            error("RFFORM002", "Form rules use the bounded vocabulary `.nonEmpty` and `.equals(\"otherField\")`.",
                  "Keep business validation in a model action; declare only field presence and equality here",
                  at: expression)
            return nil
        }
        switch member.declName.baseName.text {
        case "nonEmpty":
            guard call == nil, member.declName.argumentNames == nil else {
                error("RFFORM002", "`.nonEmpty` takes no arguments.",
                      "Use `.nonEmpty` or `.equals(\"otherField\")`", at: member)
                return nil
            }
            return .nonEmpty
        case "equals":
            guard member.declName.argumentNames == nil, let call, call.trailingClosure == nil,
                  call.arguments.count == 1, call.arguments.first?.label == nil,
                  let other = stringLiteral(call.arguments.first!.expression) else {
                error("RFFORM002", "`.equals` needs one sibling String field name literal.",
                      "Use `.equals(\"confirmation\")`", at: expression)
                return nil
            }
            return .equals(other)
        default:
            error("RFFORM002", "Unknown form rule `.\(member.declName.baseName.text)`.",
                  "Use `.nonEmpty` or `.equals(\"otherField\")`; other rules belong in native model code", at: member)
            return nil
        }
    }

    /// A form's own fields, sibling references and collisions are validated once per screen.
    func validateForms(_ declarations: [FormDeclaration]) -> Bool {
        for form in declarations {
            for field in form.fields {
                if currentModels.contains(where: { $0.propertyName == form.name }) {
                    diagnostics.append(Diagnostic(code: "RFFORM001",
                        message: "Form `\(form.name)` collides with a model input of the same name.",
                        suggestion: "Give the form a distinct name", location: form.location))
                    return false
                }
                for rule in field.rules {
                    guard case let .equals(other) = rule else { continue }
                    guard let sibling = form.field(named: other), sibling.type == field.type else {
                        diagnostics.append(Diagnostic(code: "RFFORM003",
                            message: "Field `\(field.name)` compares against `\(other)`, which is not a sibling field of the same type.",
                            suggestion: "Use `.equals` with another declared String field of the same form",
                            location: field.location ?? form.location))
                        return false
                    }
                }
            }
        }
        return true
    }

    /// `Form { ... } (form: $form)` keeps SwiftUI's native grouping and typing without adding a
    /// new view tree: it lowers to the same native container as `VStack`.
    func formContainer(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let inner = call.calledExpression.as(FunctionCallExprSyntax.self) ?? call
        guard inner.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Form",
              inner.arguments.isEmpty, inner.additionalTrailingClosures.isEmpty,
              call.arguments.map(\.label?.text) == ["form"],
              let projection = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              form(named: String(projection.baseName.text.dropFirst())) != nil else {
            error("RFFORM001", "`Form` requires a declared form and a view-builder child closure.",
                  "Use `Form { ... } (form: $form)` with a `@State private var form = refractForm { ... }` declaration",
                  at: call)
            return nil
        }
        guard let closure = call.trailingClosure ?? inner.trailingClosure else {
            error("RFFORM001", "`Form` requires a declared form and a view-builder child closure.",
                  "Use `Form { ... } (form: $form)` with a `@State private var form = refractForm { ... }` declaration",
                  at: call)
            return nil
        }
        // A rejected submit action already carries its specific diagnostic; keep the container.
        let before = diagnostics.count
        guard let children = children(of: closure) else {
            if diagnostics.count == before {
                error("RFFORM001", "`Form` requires a declared form and a view-builder child closure.",
                      "Use `Form { ... } (form: $form)` with a `@State private var form = refractForm { ... }` declaration",
                      at: call)
            }
            return nil
        }
        return .stack(axis: .vertical, children: children, modifiers: [], location: location(of: call))
    }

    /// `form.submit(model.submit)` as the single statement of a button action.
    func formSubmit(_ expression: ExprSyntax) -> StateAction? {
        guard let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "submit", member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let declaration = form(named: base.baseName.text) else { return nil }
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              let actionReference = call.arguments.first?.expression.as(MemberAccessExprSyntax.self),
              actionReference.declName.argumentNames == nil,
              let modelBase = actionReference.base?.as(DeclReferenceExprSyntax.self),
              let model = currentModels.first(where: { $0.propertyName == modelBase.baseName.text }),
              let contract = models.first(where: { $0.name == model.protocolName }),
              let action = contract.actions.first(where: { $0.name == actionReference.declName.baseName.text }) else {
            error("RFFORM004", "`\(declaration.name).submit` takes one declared model action reference.",
                  "Use `\(declaration.name).submit(model.action)` where the model declares `@refractAsync func action(...)`",
                  at: call)
            return nil
        }
        guard action.effect == .asyncAttempt else {
            error("RFFORM004", "Model action `\(action.name)` is not an asynchronous attempt and cannot submit a form.",
                  "Declare `@refractAsync func \(action.name)(...)` so the native model owns the attempt and its pending state",
                  at: actionReference)
            return nil
        }
        var arguments: [FormSubmitArgument] = []
        for parameter in action.parameters {
            guard let field = declaration.field(named: parameter.localName), field.type == parameter.type else {
                error("RFFORM004",
                      "Form `\(declaration.name)` cannot supply `\(parameter.localName): \(parameter.type.rawValue)` for `\(action.name)`.",
                      "Declare a form field whose name and type match every action parameter, in the model's parameter order",
                      at: actionReference)
                return nil
            }
            arguments.append(FormSubmitArgument(label: parameter.externalName, field: field.name))
        }
        return .submit(FormSubmit(form: declaration.name, model: model.propertyName, action: action.name,
                                  arguments: arguments, declaration: declaration, location: location(of: expression)))
    }

    /// `.disabled(model.submitting)` is how the source expresses duplicate-submit prevention:
    /// the model's own observable pending flag drives the native enabled state.
    func disabledModifier(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label == nil, call.trailingClosure == nil,
              let argument = call.arguments.first?.expression,
              let member = argument.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let property = contract.properties.first(where: { $0.name == member.declName.baseName.text }),
              property.type == .bool, property.effect == nil, property.collection == nil else {
            error("RFFORM007", "`.disabled` requires one declared Bool model property such as a pending flag.",
                  "Use `.disabled(model.submitting)`; computed conditions stay in the native model", at: call)
            return nil
        }
        let modifier = Modifier(name: "disabled",
                                arguments: [Expression(.valueProperty(.model(model: reference.propertyName,
                                                                             property: property.name)),
                                                       type: .bool, location: location(of: argument))],
                                argumentLabels: [nil], location: location(of: call))
        guard let updated = node.appendingModifier(modifier) else {
            error("unsupportedModifierTarget", "`.disabled` applies to a supported control.",
                  "Apply it directly to the Button or Toggle it gates", at: call)
            return nil
        }
        return updated
    }

    /// `refractPresent(model.submissionError)` as a typed Boolean condition.
    func presenceCondition(_ expression: ExprSyntax) -> Expression? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractPresent" else { return nil }
        guard call.arguments.count == 1, call.arguments.first?.label == nil, call.trailingClosure == nil else {
            error("RFFORM006", "`refractPresent` takes one optional model text property.",
                  "Use `if refractPresent(model.submissionError) { ... }`", at: call)
            return nil
        }
        guard let argument = call.arguments.first?.expression,
              let member = argument.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let property = contract.properties.first(where: { $0.name == member.declName.baseName.text }),
              property.effect == .text else {
            error("RFFORM006", "`refractPresent` requires a property declared with `@refractText`.",
                  "Declare `@refractText var submissionError: String { get }` on the model", at: call)
            return nil
        }
        return Expression(.presence(Expression(.valueProperty(.model(model: reference.propertyName,
                                                                     property: property.name)),
                                              location: location(of: argument))),
                          type: .bool, location: location(of: expression))
    }
}
