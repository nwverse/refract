/// The bounded callback types of the native text-input host. These are declarations,
/// never target-source templates or runtime-dispatched closures.
extension NativeParameterType {
    public var isAction: Bool { self == .action || self == .actionString }
}

extension NativeDeclaration {
    public enum Kind: String, Codable, Sendable {
        case component
        case textInputHost
    }
}
