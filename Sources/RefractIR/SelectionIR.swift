/// An immutable literal text selection configuration for an explicitly mapped native host.
/// Offsets are UTF-16 code units; empty ranges are valid, link ranges are not.
public struct SelectionRange: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct SelectionLink: Codable, Equatable, Sendable {
    public let range: SelectionRange
    public let destination: String
    public init(range: SelectionRange, destination: String) {
        self.range = range
        self.destination = destination
    }
}

public struct SelectionContent: Codable, Equatable, Sendable {
    public let text: String
    public let links: [SelectionLink]
    public init(text: String, links: [SelectionLink] = []) {
        self.text = text
        self.links = links
    }
}
