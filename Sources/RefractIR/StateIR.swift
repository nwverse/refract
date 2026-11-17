/// A get-only scalar property and a synchronous Void action form the native data boundary.
public struct ModelProperty: Codable, Equatable, Sendable {
    public let name: String
    public let type: ValueType
    public let collection: ModelCollection?
    public let location: SourceLocation?
    public init(name: String, type: ValueType, collection: ModelCollection? = nil, location: SourceLocation? = nil) {
        self.name = name
        self.type = type
        self.collection = collection
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case name, type, collection, location }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(ValueType.self, forKey: .type)
        collection = try values.decodeIfPresent(ModelCollection.self, forKey: .collection)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

public struct ModelParameter: Codable, Equatable, Sendable {
    public let externalName: String?
    public let localName: String
    public let type: ValueType
    public init(externalName: String?, localName: String, type: ValueType) {
        self.externalName = externalName
        self.localName = localName
        self.type = type
    }
}

public struct ModelAction: Codable, Equatable, Sendable {
    public let name: String
    public let parameters: [ModelParameter]
    public let location: SourceLocation?
    public init(name: String, parameters: [ModelParameter] = [], location: SourceLocation? = nil) {
        self.name = name
        self.parameters = parameters
        self.location = location
    }
}

public struct ModelProtocol: Codable, Equatable, Sendable {
    public let name: String
    public let properties: [ModelProperty]
    public let actions: [ModelAction]
    public let location: SourceLocation?
    public init(name: String, properties: [ModelProperty] = [], actions: [ModelAction] = [],
                location: SourceLocation? = nil) {
        self.name = name
        self.properties = properties
        self.actions = actions
        self.location = location
    }
}

public struct ActionArgument: Codable, Equatable, Sendable {
    public let label: String?
    public let value: Expression
    public init(label: String?, value: Expression) {
        self.label = label
        self.value = value
    }
}


/// A checked read/write path for a Bool property of the current typed list item.
/// The application model owns the mutation; no item observer or runtime adapter is involved.
public struct ItemBinding: Codable, Equatable, Sendable {
    public let model: String
    public let item: String
    public let property: String
    public let key: String
    public let action: String

    public init(model: String, item: String, property: String, key: String, action: String) {
        self.model = model
        self.item = item
        self.property = property
        self.key = key
        self.action = action
    }
}

public enum ValueProperty: Codable, Equatable, Sendable {
    case state(String)
    case binding(String)
    case model(model: String, property: String)
    case itemBinding(ItemBinding)
}

public enum WritableProperty: Codable, Equatable, Sendable {
    case state(String)
    case binding(String)
}

public enum StateAction: Codable, Equatable, Sendable {
    case assign(WritableProperty, Expression)
    case increment(WritableProperty, Expression)
    case modelMethod(model: String, name: String, arguments: [ActionArgument])
    case hostMethod(host: String, capability: NativeHostCapability, name: String, arguments: [ActionArgument])
}

public enum StringInterpolationSegment: Codable, Equatable, Sendable {
    case literal(String)
    case expression(Expression)
}
