/// A mapped design-system call, distinct from a source-declared RefractNativeView implementation.
public struct ComponentReference: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [NativeArgument]
    public let children: [ViewNode]
    public let modifiers: [Modifier]

    public init(name: String, arguments: [NativeArgument] = [], children: [ViewNode] = [], modifiers: [Modifier] = []) {
        self.name = name
        self.arguments = arguments
        self.children = children
        self.modifiers = modifiers
    }
}
