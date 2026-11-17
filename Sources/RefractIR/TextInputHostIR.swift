/// A String-consuming callback is restricted to the bounded host. The generic
/// no-argument action retains its separately defined upstream semantics.
extension NativeParameterType {
    public var isAction: Bool { self == .actionString }
}

extension NativeDeclaration {
    public enum Kind: String, Codable, Sendable {
        case component
        case textInputHost
    }
}
