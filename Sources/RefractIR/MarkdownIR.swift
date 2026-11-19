/// A bounded, source-owned rich-text document. This is a structural AST, not Markdown source to be interpreted later.
public struct MarkdownDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let blocks: [Block]

    public init(version: Int, blocks: [Block]) {
        self.version = version
        self.blocks = blocks
    }

    public enum Block: Codable, Equatable, Sendable {
        case paragraph(Paragraph)
        case codeBlock(CodeBlock)
    }

    public struct Paragraph: Codable, Equatable, Sendable {
        public let id: String
        public let content: [Inline]
        public let location: SourceLocation?

        public init(id: String, content: [Inline], location: SourceLocation? = nil) {
            self.id = id
            self.content = content
            self.location = location
        }
    }

    public struct CodeBlock: Codable, Equatable, Sendable {
        public let id: String
        public let language: Language
        public let accessibilityLabel: LocalizedText
        public let code: String
        public let location: SourceLocation?

        public init(id: String, language: Language, accessibilityLabel: LocalizedText, code: String,
                    location: SourceLocation? = nil) {
            self.id = id
            self.language = language
            self.accessibilityLabel = accessibilityLabel
            self.code = code
            self.location = location
        }
    }

    /// A closed set of typed nodes. No case carries HTML, Kotlin, ArkTS, a closure or a runtime lookup key.
    public indirect enum Inline: Codable, Equatable, Sendable {
        case text(Expression)
        case strong(Inline)
        case emphasis(Inline)
        case inlineCode(String)
        case link(Link)
    }

    public struct Link: Codable, Equatable, Sendable {
        public let label: Expression
        public let destination: Destination
        public let location: SourceLocation?

        public init(label: Expression, destination: Destination, location: SourceLocation? = nil) {
            self.label = label
            self.destination = destination
            self.location = location
        }
    }

    public struct Destination: Codable, Equatable, Sendable {
        public let scheme: String
        public let host: String
        public let path: String

        public init(scheme: String, host: String, path: String) {
            self.scheme = scheme
            self.host = host
            self.path = path
        }
    }

    public enum Language: String, Codable, Sendable { case swift, kotlin, typescript }
}

public extension MarkdownDocument.Block {
    var stableID: String {
        switch self {
        case let .paragraph(paragraph): paragraph.id
        case let .codeBlock(code): code.id
        }
    }
}
