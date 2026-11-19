/// A typed model collection; its native observation/data-source behavior is supplied by the app.
public struct ModelCollection: Codable, Equatable, Sendable {
    public let itemType: String
    public let key: String
    public let keyType: ValueType

    public init(itemType: String, key: String = "id", keyType: ValueType) {
        self.itemType = itemType
        self.key = key
        self.keyType = keyType
    }
}

/// A statically resolved call to another generated View in the same source module.
/// Only declared model owners and immutable Identifiable items cross this boundary.
public struct ChildView: Codable, Equatable, Sendable {
    public struct Argument: Codable, Equatable, Sendable {
        public let label: String
        public let expression: String
        public init(label: String, expression: String) {
            self.label = label
            self.expression = expression
        }
    }

    public let name: String
    public let arguments: [Argument]
    public let models: [Argument]
    public let item: Argument?
    public let contentType: String?

    public init(name: String, arguments: [Argument] = [], models: [Argument] = [], item: Argument? = nil,
                contentType: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.models = models
        self.item = item
        self.contentType = contentType
    }

    private enum CodingKeys: String, CodingKey { case name, arguments, models, item, contentType }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        models = try values.decode([Argument].self, forKey: .models)
        item = try values.decodeIfPresent(Argument.self, forKey: .item)
        contentType = try values.decodeIfPresent(String.self, forKey: .contentType)
        arguments = try values.decodeIfPresent([Argument].self, forKey: .arguments) ?? models + (item.map { [$0] } ?? [])
    }
}

/// Typed view additions shared by frontends and native backends.
public enum LayoutSpacing: String, Codable, Sendable {
    case small, medium

    public var points: Int { self == .small ? 4 : 8 }
}

public struct LayoutContainer: Codable, Equatable, Sendable {
    public let axis: ViewNode.StackAxis
    public let alignment: LayoutAlignment?
    public let spacing: Expression?

    public init(axis: ViewNode.StackAxis, alignment: LayoutAlignment? = nil, spacing: Expression? = nil) {
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
    }
}

public enum LayoutAlignment: String, Codable, Hashable, Sendable {
    case center, leading, trailing, top, bottom, topLeading, bottomTrailing
}

public struct ImageSource: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case system, application }
    public let kind: Kind
    public let name: String
    public let location: SourceLocation?

    public init(kind: Kind, name: String, location: SourceLocation? = nil) {
        self.kind = kind
        self.name = name
        self.location = location
    }
}

/// A finite category projection over an identified item collection. The iOS support
/// declaration returns the already filtered and sorted array; no runtime descriptor exists.
public struct CollectionProjection: Codable, Equatable, Sendable {
    public let name: String
    public let categoryProperty: String
    public let categoryEnum: String
    public let categoryParameter: String
    public let sortProperty: String
    public let ascending: Bool

    public init(name: String, categoryProperty: String, categoryEnum: String, categoryParameter: String,
                sortProperty: String, ascending: Bool) {
        self.name = name
        self.categoryProperty = categoryProperty
        self.categoryEnum = categoryEnum
        self.categoryParameter = categoryParameter
        self.sortProperty = sortProperty
        self.ascending = ascending
    }
}

/// A lazy collection already exposed by the application model as an ArkUI-compatible data source.
public struct ListItems: Codable, Equatable, Sendable {
    public let collection: Expression
    /// The frontend-resolved protocol that owns this collection, not a name guessed
    /// from a property shared by two models.
    public let modelType: String?
    public let itemName: String
    public let itemType: String
    public let key: String
    public let keyType: ValueType
    public let content: ViewNode
    public let contentType: String?
    /// The bounded message child identity; its content belongs to the outer ListItems.
    public let messageBlocks: MessageBlockIdentity?
    public let projection: CollectionProjection?
    public let location: SourceLocation?

    public init(collection: Expression, itemName: String, itemType: String, key: String = "id",
                keyType: ValueType, content: ViewNode, contentType: String? = nil,
                projection: CollectionProjection? = nil, modelType: String? = nil,
                messageBlocks: MessageBlockIdentity? = nil, location: SourceLocation? = nil) {
        self.collection = collection
        self.modelType = modelType
        self.itemName = itemName
        self.itemType = itemType
        self.key = key
        self.keyType = keyType
        self.content = content
        self.contentType = contentType
        self.messageBlocks = messageBlocks
        self.projection = projection
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case collection, modelType, itemName, itemType, key, keyType, content, contentType, messageBlocks, projection, location }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        collection = try values.decode(Expression.self, forKey: .collection)
        modelType = try values.decodeIfPresent(String.self, forKey: .modelType)
        itemName = try values.decode(String.self, forKey: .itemName)
        itemType = try values.decode(String.self, forKey: .itemType)
        key = try values.decode(String.self, forKey: .key)
        keyType = try values.decode(ValueType.self, forKey: .keyType)
        content = try values.decode(ViewNode.self, forKey: .content)
        contentType = try values.decodeIfPresent(String.self, forKey: .contentType)
        messageBlocks = try values.decodeIfPresent(MessageBlockIdentity.self, forKey: .messageBlocks)
        projection = try values.decodeIfPresent(CollectionProjection.self, forKey: .projection)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

/// The bounded child content of a message list, without a recursive ListItems ownership cycle.
public struct MessageBlockIdentity: Codable, Equatable, Sendable {
    public let content: ViewNode
    public let parent: String
    public let blockName: String
    public let blockArgument: ChildView.Argument

    public init(content: ViewNode, parent: String, blockName: String, blockArgument: ChildView.Argument) {
        self.content = content
        self.parent = parent
        self.blockName = blockName
        self.blockArgument = blockArgument
    }
}

/// A bounded direct ForEach nested in one ChatMessage row's non-scrolling content.
public struct NestedListItems: Codable, Equatable, Sendable {
    public let items: ListItems
    /// The caller's parent expression, distinct from the child's `message` parameter name.
    public let parent: String?
    /// The checked message input of the nested presentation child.
    public let message: ChildView.Argument?
    /// The checked block input of the nested presentation child.
    public let block: ChildView.Argument?

    public init(_ items: ListItems, parent: String? = nil,
                message: ChildView.Argument? = nil, block: ChildView.Argument? = nil) {
        self.items = items
        self.parent = parent
        self.message = message
        self.block = block
    }
}

/// One bounded, immutable collection owned by a ChatMessage item snapshot.
/// The projection contract resolves it to an app-owned native ForEach.
public struct ItemCollection: Codable, Equatable, Sendable {
    public let itemType: String
    public let owner: String
    public let property: String

    public init(itemType: String, owner: String = "", property: String = "") {
        self.itemType = itemType
        self.owner = owner
        self.property = property
    }
}

public struct ItemProperty: Codable, Equatable, Sendable {
    public let name: String
    public let type: ValueType
    public let collection: ItemCollection?
    /// The exact source spelling, retained for a bounded projection declaration.
    public let declaredType: String?
    public let enumName: String?

    public init(name: String, type: ValueType, collection: ItemCollection? = nil,
                declaredType: String? = nil, enumName: String? = nil) {
        self.name = name
        self.type = type
        self.collection = collection
        self.declaredType = declaredType
        self.enumName = enumName
    }

    private enum CodingKeys: String, CodingKey { case name, type, collection, declaredType, enumName }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(ValueType.self, forKey: .type)
        collection = try values.decodeIfPresent(ItemCollection.self, forKey: .collection)
        declaredType = try values.decodeIfPresent(String.self, forKey: .declaredType)
        enumName = try values.decodeIfPresent(String.self, forKey: .enumName)
    }
}

public struct ItemType: Codable, Equatable, Sendable {
    public let name: String
    public let identity: ItemProperty
    public let properties: [ItemProperty]
    public let location: SourceLocation?
    /// The bounded message/block declarations own their source revision and collection semantics.
    public let messageProjection: Bool

    public init(name: String, identity: ItemProperty, properties: [ItemProperty], location: SourceLocation? = nil,
                messageProjection: Bool = false) {
        self.name = name
        self.identity = identity
        self.properties = properties
        self.location = location
        self.messageProjection = messageProjection
    }

    private enum CodingKeys: String, CodingKey { case name, identity, properties, location, messageProjection }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        identity = try values.decode(ItemProperty.self, forKey: .identity)
        properties = try values.decode([ItemProperty].self, forKey: .properties)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
        messageProjection = try values.decodeIfPresent(Bool.self, forKey: .messageProjection) ?? false
    }
}

public extension ViewNode {
    func children(for platform: TargetPlatform) -> [ViewNode] {
        if case let .platformView(alternatives, _) = self {
            return platform == .android ? alternatives.android : alternatives.harmonyOS
        }
        return children
    }

    var children: [ViewNode] {
        switch self {
        case let .stack(_, children, _, _), let .layout(_, children, _, _), let .list(children, _, _): children
        case let .scroll(_, child, _, _), let .listItem(child, _), let .nativeModifier(child, _, _): [child]
        case let .button(label, _, _, _): [label]
        case let .section(_, children, _): children
        case let .component(component, _): component.children
        case let .forEach(items, _): [items.content]
        case let .messageBlocks(nested, _): [nested.items.content]
        case let .conditional(branches, _): branches.flatMap(\.children)
        case let .optionalBinding(_, _, children, otherwise, _): children + otherwise
        case let .switchExpression(_, _, cases, _): cases.flatMap(\.children)
        case let .navigationStack(stack, _): stack.content
        case .tabView: []
        case let .platformView(alternatives, _): alternatives.ios + alternatives.android + alternatives.harmonyOS
        default: []
        }
    }

    var sourceLocation: SourceLocation? {
        switch self {
        case let .stack(_, _, _, location), let .text(_, _, location), let .markdown(_, _, _, location), let .button(_, _, _, location),
             let .native(_, location), let .nativeModifier(_, _, location), let .component(_, location),
             let .child(_, location), let .platformView(_, location), let .conditional(_, location),
             let .layout(_, _, _, location), let .scroll(_, _, _, location), let .list(_, _, location),
             let .section(_, _, location), let .listItem(_, location), let .forEach(_, location),
             let .image(_, _, location), let .toggle(_, _, _, _, _, location), let .textInput(_, _, _, location),
             let .secureInput(_, _, _, _, location),
             let .label(_, _, _, location), let .divider(_, location), let .spacer(location),
             let .switchExpression(_, _, _, location), let .optionalBinding(_, _, _, _, location),
             let .messageBlocks(_, location),
             let .navigationLink(_, _, _, _, location), let .navigationStack(_, location), let .tabView(_, location): location
        }
    }
}
