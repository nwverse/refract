/// A finite, source-owned navigation destination identity.
/// A host-owned push operation. Its finite enum is resolved in the source navigation graph.
public struct NavigationOperation: Codable, Equatable, Sendable {
    public let pathName: String
    public let enumName: String

    public init(pathName: String = "path", enumName: String) {
        self.pathName = pathName
        self.enumName = enumName
    }
}

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
