/// A document link is a source model action. The app, not a URL-opening runtime, owns activation policy.
public struct MarkdownLinkAction: Codable, Equatable, Sendable {
    public let model: String
    public let method: String
    public let argumentLabel: String?

    public init(model: String, method: String, argumentLabel: String? = nil) {
        self.model = model
        self.method = method
        self.argumentLabel = argumentLabel
    }
}
