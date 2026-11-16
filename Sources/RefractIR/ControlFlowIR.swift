/// A locally declared finite enum whose cases carry no payload or raw value.
public struct EnumDeclaration: Codable, Equatable, Sendable {
    public let name: String
    public let cases: [String]
    public let location: SourceLocation?

    public init(name: String, cases: [String], location: SourceLocation? = nil) {
        self.name = name
        self.cases = cases
        self.location = location
    }
}

public struct SwitchCase: Codable, Equatable, Sendable {
    public let name: String
    public let children: [ViewNode]

    public init(name: String, children: [ViewNode]) {
        self.name = name
        self.children = children
    }
}
