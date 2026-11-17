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

/// A source NavigationStack declaration. Native hosts own the actual stack and push/pop callbacks.
public struct NavigationStackNode: Codable, Equatable, Sendable {
    public let pathName: String
    public let enumName: String
    public let content: [ViewNode]
    public let destinations: [NavigationDestination]

    public init(pathName: String, enumName: String, content: [ViewNode], destinations: [NavigationDestination]) {
        self.pathName = pathName
        self.enumName = enumName
        self.content = content
        self.destinations = destinations
    }
}
