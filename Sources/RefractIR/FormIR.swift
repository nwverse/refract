/// Typed, bounded form declarations. The generator type-checks field rules and lowers them to
/// native comparisons and guards; the application's model owns every business rule, submission
/// attempt and error message. No Swift validation body is translated and no rule is evaluated
/// by a target template.
public struct FormField: Codable, Equatable, Sendable {
    /// The bounded rule vocabulary. `equals` names a sibling String field in the same form.
    public enum Rule: Codable, Equatable, Sendable {
        case nonEmpty
        case equals(String)
    }

    public let name: String
    public let type: ValueType
    public let initialValue: Expression
    public let rules: [Rule]
    public let location: SourceLocation?

    public init(name: String, type: ValueType = .string, initialValue: Expression, rules: [Rule] = [],
                location: SourceLocation? = nil) {
        self.name = name
        self.type = type
        self.initialValue = initialValue
        self.rules = rules
        self.location = location
    }
}

public struct FormDeclaration: Codable, Equatable, Sendable {
    public let name: String
    public let fields: [FormField]
    public let location: SourceLocation?

    public init(name: String, fields: [FormField], location: SourceLocation? = nil) {
        self.name = name
        self.fields = fields
        self.location = location
    }

    public func field(named name: String) -> FormField? {
        fields.first { $0.name == name }
    }
}

/// One `form.field` argument of a checked `form.submit(model.action)` statement.
public struct FormSubmitArgument: Codable, Equatable, Sendable {
    public let label: String?
    public let field: String
    public init(label: String?, field: String) {
        self.label = label
        self.field = field
    }
}

/// A typed submission: the model action accepts the form's current draft values. Lowering guards
/// the call with the form's own declared rules; pending/duplicate gating reads the model's
/// observable state through the button's enabled flag, never through a generated flag.
public struct FormSubmit: Codable, Equatable, Sendable {
    public let form: String
    public let model: String
    public let action: String
    public let arguments: [FormSubmitArgument]
    /// The checked declaration, so a backend never re-derives rules from source text.
    public let declaration: FormDeclaration?
    public let location: SourceLocation?

    public init(form: String, model: String, action: String, arguments: [FormSubmitArgument],
                declaration: FormDeclaration? = nil, location: SourceLocation? = nil) {
        self.form = form
        self.model = model
        self.action = action
        self.arguments = arguments
        self.declaration = declaration
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case form, model, action, arguments, declaration, location }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        form = try values.decode(String.self, forKey: .form)
        model = try values.decode(String.self, forKey: .model)
        action = try values.decode(String.self, forKey: .action)
        arguments = try values.decode([FormSubmitArgument].self, forKey: .arguments)
        declaration = try values.decodeIfPresent(FormDeclaration.self, forKey: .declaration)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}
