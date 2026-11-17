/// A typed owner for native presentation. The Boolean is observed by the host;
/// it is never lowered into an ordinary layout conditional.
public struct ModalPresentation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case sheet, alert }

    public let kind: Kind
    public let stateName: String
    public let isBinding: Bool
    public let title: Expression?
    public let message: Expression?
    public let confirmTitle: Expression?
    public let cancelTitle: Expression?
    public let confirmAction: StateAction?
    public let content: [ViewNode]

    public init(kind: Kind, stateName: String, isBinding: Bool, title: Expression? = nil,
                message: Expression? = nil, confirmTitle: Expression? = nil,
                cancelTitle: Expression? = nil, confirmAction: StateAction? = nil,
                content: [ViewNode] = []) {
        self.kind = kind
        self.stateName = stateName
        self.isBinding = isBinding
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.confirmAction = confirmAction
        self.content = content
    }
}
