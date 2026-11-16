import Foundation
import RefractIR

/// A JSON tree with source coordinates. This is intentionally separate from the public, typed mapping model.
struct MappingJSONDocument {
    enum Value {
        case object([(String, Value, SourceLocation)], SourceLocation)
        case array([Value], SourceLocation)
        case string(String, SourceLocation)
        case number(String, SourceLocation)
        case bool(Bool, SourceLocation)
        case null(SourceLocation)

        var location: SourceLocation {
            switch self {
            case let .object(_, at), let .array(_, at), let .string(_, at), let .number(_, at),
                 let .bool(_, at), let .null(at): at
            }
        }

        var typeName: String {
            switch self {
            case .object: "object"
            case .array: "array"
            case .string: "string"
            case .number: "number"
            case .bool: "boolean"
            case .null: "null"
            }
        }

        func property(_ name: String) -> Value? { object?.last { $0.0 == name }?.1 }
        var object: [(String, Value, SourceLocation)]? { if case let .object(values, _) = self { values } else { nil } }
        var array: [Value]? { if case let .array(values, _) = self { values } else { nil } }
        var string: String? { if case let .string(value, _) = self { value } else { nil } }
        var number: String? { if case let .number(value, _) = self { value } else { nil } }
        var bool: Bool? { if case let .bool(value, _) = self { value } else { nil } }
    }

    let root: Value
    let file: String

    init(data: Data, file: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MappingError(diagnostics: [Diagnostic(code: "mappingIO", message: "The mapping is not UTF-8 text.",
                suggestion: "Save refract.json as UTF-8 without a byte-order mark.",
                location: SourceLocation(file: file, line: 1, column: 1))])
        }
        var parser = Parser(text: text, file: file)
        do {
            root = try parser.document()
            self.file = file
        } catch let error as MappingError { throw error }
    }

    struct Duplicate {
        let key: String
        let path: String
        let location: SourceLocation
    }

    func duplicates(in value: Value? = nil, path: String = "root") -> [Duplicate] {
        let value = value ?? root
        guard let object = value.object else {
            return value.array?.enumerated().flatMap { duplicates(in: $0.element, path: "\(path)[\($0.offset)]") } ?? []
        }
        var seen: Set<String> = []
        var result: [Duplicate] = []
        for (key, child, keyLocation) in object {
            if !seen.insert(key).inserted {
                result.append(Duplicate(key: key, path: path, location: keyLocation))
            }
            result.append(contentsOf: duplicates(in: child, path: path == "root" ? key : "\(path).\(key)"))
        }
        return result
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        let file: String
        var offset = 0

        init(text: String, file: String) {
            scalars = Array(text.unicodeScalars)
            self.file = file
        }

        mutating func document() throws -> Value {
            whitespace()
            let value = try self.value()
            whitespace()
            guard offset == scalars.count else { throw syntax("Unexpected content after the JSON document.") }
            return value
        }

        mutating func value() throws -> Value {
            whitespace()
            guard let scalar = peek() else { throw syntax("Expected a JSON value.") }
            let start = offset
            switch scalar {
            case "{":
                advance()
                whitespace()
                var properties: [(String, Value, SourceLocation)] = []
                if peek() == "}" {
                    advance()
                    return .object(properties, location(start))
                }
                while true {
                    whitespace()
                    guard peek() == "\"" else { throw syntax("Expected a quoted JSON object key.") }
                    let keyStart = offset
                    let key = try string()
                    let keyLocation = location(keyStart)
                    whitespace()
                    try expect(":")
                    properties.append((key, try value(), keyLocation))
                    whitespace()
                    if peek() == "}" { advance(); break }
                    try expect(",")
                }
                return .object(properties, location(start))
            case "[":
                advance()
                whitespace()
                var values: [Value] = []
                if peek() == "]" { advance(); return .array(values, location(start)) }
                while true {
                    values.append(try value())
                    whitespace()
                    if peek() == "]" { advance(); break }
                    try expect(",")
                }
                return .array(values, location(start))
            case "\"":
                return .string(try string(), location(start))
            case "t":
                try literal("true")
                return .bool(true, location(start))
            case "f":
                try literal("false")
                return .bool(false, location(start))
            case "n":
                try literal("null")
                return .null(location(start))
            case "-", "0"..."9":
                var text = ""
                if peek() == "-" { text.append("-"); advance() }
                guard let first = peek(), ("0"..."9").contains(first) else { throw syntax("Expected a digit after `-`.") }
                if first == "0" {
                    text.append("0"); advance()
                    if let next = peek(), ("0"..."9").contains(next) { throw syntax("A JSON number cannot have a leading zero.") }
                } else {
                    while let next = peek(), ("0"..."9").contains(next) { text.append(Character(next)); advance() }
                }
                if peek() == "." {
                    text.append("."); advance()
                    guard let next = peek(), ("0"..."9").contains(next) else { throw syntax("Expected a digit after the decimal point.") }
                    while let next = peek(), ("0"..."9").contains(next) { text.append(Character(next)); advance() }
                }
                if let next = peek(), next == "e" || next == "E" {
                    text.append(Character(next)); advance()
                    if let sign = peek(), sign == "+" || sign == "-" { text.append(Character(sign)); advance() }
                    guard let next = peek(), ("0"..."9").contains(next) else { throw syntax("Expected an exponent digit.") }
                    while let next = peek(), ("0"..."9").contains(next) { text.append(Character(next)); advance() }
                }
                return .number(text, location(start))
            default:
                throw syntax("Unexpected character `\(Character(scalar))` in JSON.")
            }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var result = ""
            while let scalar = peek() {
                advance()
                if scalar == "\"" { return result }
                if scalar.value < 0x20 { throw syntax("An unescaped control character is not allowed in a JSON string.", offset - 1) }
                if scalar != "\\" { result.unicodeScalars.append(scalar); continue }
                guard let escape = peek() else { throw syntax("Unterminated JSON escape sequence.") }
                advance()
                switch escape {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{8}")
                case "f": result.append("\u{c}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    let first = try hex()
                    if (0xD800...0xDBFF).contains(first) {
                        try expect("\\")
                        try expect("u")
                        let second = try hex()
                        guard (0xDC00...0xDFFF).contains(second), let unicode = Unicode.Scalar(
                            0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)) else {
                            throw syntax("Invalid Unicode surrogate pair.")
                        }
                        result.unicodeScalars.append(unicode)
                    } else if (0xDC00...0xDFFF).contains(first) {
                        throw syntax("Unexpected low Unicode surrogate.")
                    } else if let unicode = Unicode.Scalar(first) {
                        result.unicodeScalars.append(unicode)
                    }
                default: throw syntax("Invalid JSON escape sequence.")
                }
            }
            throw syntax("Unterminated JSON string.")
        }

        mutating func hex() throws -> UInt32 {
            var result: UInt32 = 0
            for _ in 0..<4 {
                guard let scalar = peek() else {
                    throw syntax("Expected four hexadecimal digits in a Unicode escape.")
                }
                let value: UInt32
                switch scalar {
                case "0"..."9": value = scalar.value - Unicode.Scalar("0").value
                case "a"..."f": value = scalar.value - Unicode.Scalar("a").value + 10
                case "A"..."F": value = scalar.value - Unicode.Scalar("A").value + 10
                default: throw syntax("Expected four hexadecimal digits in a Unicode escape.")
                }
                result = result * 16 + UInt32(value)
                advance()
            }
            return result
        }

        mutating func literal(_ text: String) throws {
            for scalar in text.unicodeScalars {
                guard peek() == scalar else { throw syntax("Invalid JSON literal.") }
                advance()
            }
        }

        mutating func expect(_ scalar: Unicode.Scalar) throws {
            guard peek() == scalar else { throw syntax("Expected `\(Character(scalar))`.") }
            advance()
        }

        func peek() -> Unicode.Scalar? { offset < scalars.count ? scalars[offset] : nil }
        mutating func advance() { offset += 1 }
        mutating func whitespace() {
            while let scalar = peek(), scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                advance()
            }
        }
        func location(_ at: Int) -> SourceLocation {
            var line = 1, column = 1
            for scalar in scalars[..<max(0, min(at, scalars.count))] {
                if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
            }
            return SourceLocation(file: file, line: line, column: column)
        }
        func syntax(_ message: String, _ at: Int? = nil) -> MappingError {
            MappingError(diagnostics: [Diagnostic(code: "mappingSyntax", message: message,
                suggestion: "Correct the JSON syntax before generating code.", location: location(at ?? offset))])
        }
    }
}
