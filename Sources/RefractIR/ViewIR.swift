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

/// A lazy collection already exposed by the application model as an ArkUI-compatible data source.
public struct ListItems: Codable, Equatable, Sendable {
    public let collection: Expression
    public let itemName: String
    public let itemType: String
    public let key: String
    public let keyType: ValueType
    public let content: ViewNode
    public let location: SourceLocation?

    public init(collection: Expression, itemName: String, itemType: String, key: String = "id",
                keyType: ValueType, content: ViewNode, location: SourceLocation? = nil) {
        self.collection = collection
        self.itemName = itemName
        self.itemType = itemType
        self.key = key
        self.keyType = keyType
        self.content = content
        self.location = location
    }
}

public struct ItemProperty: Codable, Equatable, Sendable {
    public let name: String
    public let type: ValueType
    public init(name: String, type: ValueType) { self.name = name; self.type = type }
}

public struct ItemType: Codable, Equatable, Sendable {
    public let name: String
    public let identity: ItemProperty
    public let properties: [ItemProperty]
    public let location: SourceLocation?

    public init(name: String, identity: ItemProperty, properties: [ItemProperty], location: SourceLocation? = nil) {
        self.name = name
        self.identity = identity
        self.properties = properties
        self.location = location
    }
}

public extension ViewNode {
    var children: [ViewNode] {
        switch self {
        case let .stack(_, children, _, _), let .layout(_, children, _, _), let .list(children, _, _): children
        case let .scroll(_, child, _, _), let .listItem(child, _): [child]
        case let .button(label, _, _, _): [label]
        case let .section(_, children, _): children
        case let .forEach(items, _): [items.content]
        case let .conditional(branches, _): branches.flatMap(\.children)
        case let .platformView(alternatives, _): alternatives.ios + alternatives.android + alternatives.harmonyOS
        default: []
        }
    }

    var sourceLocation: SourceLocation? {
        switch self {
        case let .stack(_, _, _, location), let .text(_, _, location), let .button(_, _, _, location),
             let .native(_, location), let .platformView(_, location), let .conditional(_, location),
             let .layout(_, _, _, location), let .scroll(_, _, _, location), let .list(_, _, location),
             let .section(_, _, location), let .listItem(_, location), let .forEach(_, location),
             let .image(_, _, location), let .toggle(_, _, _, location), let .textInput(_, _, _, location),
             let .label(_, _, _, location), let .divider(_, location), let .spacer(location): location
        }
    }
}
