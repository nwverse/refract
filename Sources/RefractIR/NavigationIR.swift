/// A finite, source-owned navigation destination identity.
public struct NavigationDestination: Codable, Equatable, Sendable {
    public let caseName: String
    public let viewName: String
    public let model: ChildView.Argument?

    public init(caseName: String, viewName: String, model: ChildView.Argument? = nil) {
        self.caseName = caseName
        self.viewName = viewName
        self.model = model
    }
}

/// One typed tab destination: a zero-argument generated child View with its localized tab label and system symbol.
public struct TabDestination: Codable, Equatable, Sendable {
    public let caseName: String
    public let viewName: String
    public let title: Expression
    public let symbol: String

    public init(caseName: String, viewName: String, title: Expression, symbol: String) {
        self.caseName = caseName
        self.viewName = viewName
        self.title = title
        self.symbol = symbol
    }
}

/// One bounded overflow-menu action. Only typed model actions are accepted; there is no closure registry.
public struct OverflowMenuAction: Codable, Equatable, Sendable {
    public let title: Expression
    public let action: StateAction

    public init(title: Expression, action: StateAction) {
        self.title = title
        self.action = action
    }
}

/// A bounded `TabView(selection:)` root. Native hosts own the selected tab, back behavior and tab lifecycle;
/// generated code only renders the selection bar, the overflow menu and a typed destination switch.
public struct TabViewNode: Codable, Equatable, Sendable {
    public let selectionName: String
    public let rootName: String
    public let enumName: String
    public let destinations: [TabDestination]
    public let menuTitle: Expression?
    public let menuSymbol: String?
    public let menuActions: [OverflowMenuAction]
    public let models: [ModelReference]

    public init(selectionName: String, rootName: String = "", enumName: String, destinations: [TabDestination],
                menuTitle: Expression? = nil, menuSymbol: String? = nil, menuActions: [OverflowMenuAction] = [],
                models: [ModelReference] = []) {
        self.selectionName = selectionName
        self.rootName = rootName
        self.enumName = enumName
        self.destinations = destinations
        self.menuTitle = menuTitle
        self.menuSymbol = menuSymbol
        self.menuActions = menuActions
        self.models = models
    }
}

/// A source NavigationStack declaration. Native hosts own the actual stack and push/pop callbacks.
public struct NavigationStackNode: Codable, Equatable, Sendable {
    public let pathName: String
    public let rootName: String
    public let enumName: String
    public let content: [ViewNode]
    public let destinations: [NavigationDestination]
    public let models: [ModelReference]

    public init(pathName: String, rootName: String = "", enumName: String, content: [ViewNode], destinations: [NavigationDestination],
                models: [ModelReference] = []) {
        self.pathName = pathName
        self.rootName = rootName
        self.enumName = enumName
        self.content = content
        self.destinations = destinations
        self.models = models
    }
}
