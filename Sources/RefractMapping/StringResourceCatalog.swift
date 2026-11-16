import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import RefractIR

/// The common subset of printf placeholders supported by all three platforms.
/// A single catalog is validated independently on each platform; it is never copied or rewritten.
public enum StringResourceName {
    public static func make(key: String, location: RefractIR.SourceLocation? = nil) throws -> String {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty, segments.allSatisfy({ segment in
            guard let first = segment.first, first.isASCII, first.isLetter, first.isLowercase else { return false }
            return segment.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
        }) else {
            throw Diagnostic(code: "R.string.invalid_key",
                             message: "String key `\(key)` is not a lowercase dot-separated resource key.",
                             suggestion: "Use segments such as `settings.title2`, starting with a lowercase ASCII letter and containing only lowercase ASCII letters and digits; dots become underscores in both native catalogs",
                             location: location)
        }
        // No underscores occur in keys, so this conversion is injective and reversible.
        return segments.joined(separator: "_")
    }
}

public struct StringFormat: Equatable, Sendable {
    public let arguments: [ValueType]

    public init(arguments: [ValueType]) {
        self.arguments = arguments
    }

    public static func parse(_ value: String, location: RefractIR.SourceLocation? = nil) throws -> StringFormat {
        let scalars = Array(value.unicodeScalars)
        var result: [Int: ValueType] = [:]
        var maximum = 0
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "%" else { index += 1; continue }
            index += 1
            guard index < scalars.count else { throw unsupported("a trailing `%`", location) }
            if scalars[index] == "%" { index += 1; continue }
            var position = 0
            while index < scalars.count, let digit = scalars[index].asciiDigit {
                let (next, overflow) = position.multipliedReportingOverflow(by: 10)
                let (value, additionOverflow) = next.addingReportingOverflow(digit)
                guard !overflow, !additionOverflow, value <= 1_000_000 else {
                    throw unsupported("an excessive placeholder position", location)
                }
                position = value
                index += 1
            }
            guard index < scalars.count, scalars[index] == "$" else {
                throw unsupported("a placeholder without an explicit one-based position", location)
            }
            index += 1
            guard index < scalars.count, let specifier = scalars[index].formatType,
                  position > 0, result[position] == nil else {
                throw unsupported("the placeholder near scalar \(index)", location)
            }
            result[position] = specifier
            maximum = max(maximum, position)
            index += 1
        }
        guard result.count == maximum else {
            throw unsupported("non-contiguous placeholder positions", location)
        }
        return StringFormat(arguments: maximum == 0 ? [] : (1...maximum).map { result[$0]! })
    }

    private static func unsupported(_ detail: String, _ location: RefractIR.SourceLocation?) -> Diagnostic {
        Diagnostic(code: "R.string.unsupported_format",
                   message: "String resource contains \(detail), which is not portable.",
                   suggestion: "Use %% and one-based positional %1$s, %2$d or %3$f placeholders with no width, precision, flags or length modifiers",
                   location: location)
    }
}

public struct StringResourceEntry: Equatable, Sendable {
    public let name: String
    public let value: String
    public let format: StringFormat

    public init(name: String, value: String) throws {
        self.name = name
        self.value = value
        self.format = try StringFormat.parse(value)
    }
}

public struct StringResourceCatalog: Equatable, Sendable {
    public let entries: [String: StringResourceEntry]

    public init(entries: [String: StringResourceEntry]) {
        self.entries = entries
    }
}

public enum StringResourceLoader {
    public static func load(android path: String, harmony: String,
                            base: URL? = nil) throws -> [String: StringResourceEntry] {
        let base = base ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let androidURL = resolve(path, relativeTo: base)
        let harmonyURL = resolve(harmony, relativeTo: base)
        let android = try loadAndroid(androidURL)
        let harmony = try loadHarmony(harmonyURL)
        var result = android
        for (name, entry) in harmony {
            if let existing = result[name], existing.format != entry.format {
                throw Diagnostic(code: "R.string.format_arguments",
                                 message: "Android and HarmonyOS string resource `\(name)` have incompatible placeholders.",
                                 suggestion: "Use the same ordered argument types in both catalogs")
            }
            result[name] = entry
        }
        return result
    }

    public static func loadAndroid(_ url: URL) throws -> [String: StringResourceEntry] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw invalid("cannot read Android string resources at \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let delegate = AndroidStringsDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.failure == nil else {
            throw delegate.failure ?? invalid("Android string resources are not well-formed XML: \(parser.parserError?.localizedDescription ?? "unknown XML error")")
        }
        return try unique(delegate.entries, platform: "Android")
    }

    public static func loadHarmony(_ url: URL) throws -> [String: StringResourceEntry] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw invalid("cannot read HarmonyOS string resources at \(url.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            let value = try JSONDecoder().decode(HarmonyStrings.self, from: data)
            return try unique(value.string.map { ($0.name, $0.value) }, platform: "HarmonyOS")
        } catch let error as Diagnostic {
            throw error
        } catch {
            throw invalid("HarmonyOS string resources must contain a `string` array of name/value objects: \(error.localizedDescription)")
        }
    }

    public static func resolve(_ path: String, relativeTo base: URL) -> URL {
        guard !path.isEmpty else { return base }
        let url = URL(fileURLWithPath: path, relativeTo: base)
        return url.standardizedFileURL
    }

    private static func unique(_ pairs: [(name: String, value: String)],
                               platform: String) throws -> [String: StringResourceEntry] {
        var result: [String: StringResourceEntry] = [:]
        for (name, value) in pairs {
            guard result[name] == nil else {
                throw Diagnostic(code: "R.string.duplicate_resource",
                                 message: "\(platform) declares string resource `\(name)` more than once.",
                                 suggestion: "Keep one base string entry per resource name")
            }
            guard name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil else {
                throw invalid("\(platform) string resource name `\(name)` is not a lowercase underscore resource name")
            }
            result[name] = try StringResourceEntry(name: name, value: value)
        }
        return result
    }

    private static func invalid(_ message: String) -> Diagnostic {
        Diagnostic(code: "R.string.invalid_resource", message: message,
                   suggestion: "Provide well-formed base Android strings.xml and HarmonyOS string.json files")
    }
}

private struct HarmonyStrings: Decodable {
    struct Entry: Decodable { let name: String; let value: String }
    let string: [Entry]
}

private final class AndroidStringsDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var entries: [(name: String, value: String)] = []
    var failure: Diagnostic?
    private var name: String?
    private var text = ""
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if elementName == "string" {
            guard depth == 2, name == nil, let resourceName = attributes["name"],
                  attributes["translatable"] != "false",
                  attributes.keys.allSatisfy({ ["name", "translatable", "formatted"].contains($0) }) else {
                failure = Diagnostic(code: "R.string.invalid_resource",
                                     message: "Android string resources must be direct, translatable children of <resources> with a name.",
                                     suggestion: "Move generated-screen strings into the base values/strings.xml file")
                parser.abortParsing()
                return
            }
            name = resourceName
            text = ""
        } else if name != nil {
            failure = Diagnostic(code: "R.string.invalid_resource",
                                 message: "Android string `\(name!)` contains unsupported markup <\(elementName)>.",
                                 suggestion: "Use plain text and portable positional placeholders")
            parser.abortParsing()
        } else if depth != 1 || elementName != "resources" {
            failure = Diagnostic(code: "R.string.invalid_resource",
                                 message: "Android string resources contain unsupported <\(elementName)> content.",
                                 suggestion: "Keep this catalog limited to <resources> and direct <string> children")
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if name != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if name != nil, let string = String(data: block, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if elementName == "string", let name {
            entries.append((name, text))
            self.name = nil
        }
        depth -= 1
    }
}

private extension Unicode.Scalar {
    var asciiDigit: Int? {
        guard value >= 48, value <= 57 else { return nil }
        return Int(value) - 48
    }

    var formatType: ValueType? {
        switch self {
        case "s": .string
        case "d": .int
        case "f": .double
        default: nil
        }
    }
}
