import Foundation
import RefractIR

public enum Platform: String, CaseIterable, Codable, Sendable {
    case android
    case harmonyOS

    public var displayName: String { self == .android ? "Android" : "HarmonyOS" }
}

/// A fully resolved, immutable project mapping. Backends consume these records, never raw JSON.
public struct Mapping: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let android: PlatformMapping
    public let harmonyOS: PlatformMapping

    public init(schemaVersion: Int = 1, android: PlatformMapping = .empty,
                harmonyOS: PlatformMapping = .empty) {
        self.schemaVersion = schemaVersion
        self.android = android
        self.harmonyOS = harmonyOS
    }

    public static let empty = Mapping()

    /// The machine-readable schema distributed with this version of RefractMapping.
    public static var schemaJSON: String {
        guard let url = Bundle.module.url(forResource: "refract.schema", withExtension: "json"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("The packaged refract.schema.json resource is missing.")
        }
        return contents
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, version, android, harmonyOS, nativeComponents }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.version) {
            let legacy = try LegacyMapping(from: decoder)
            self = legacy.mapping
            return
        }
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        android = try values.decode(PlatformMapping.self, forKey: .android)
        harmonyOS = try values.decode(PlatformMapping.self, forKey: .harmonyOS)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(android, forKey: .android)
        try container.encode(harmonyOS, forKey: .harmonyOS)
    }

    public static func load(contentsOf url: URL) throws -> Mapping {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            throw MappingError(diagnostics: [Diagnostic(code: "mappingIO",
                message: "The mapping file cannot be read.",
                suggestion: "Provide a readable UTF-8 refract.json file.",
                location: SourceLocation(file: url.lastPathComponent, line: 1, column: 1))])
        }
        switch validate(data: data, file: url.lastPathComponent) {
        case let .success(mapping): return mapping
        case let .failure(error): throw error
        }
    }

    public static func load(data: Data, file: String = "refract.json") throws -> Mapping {
        switch validate(data: data, file: file) {
        case let .success(mapping): return mapping
        case let .failure(error): throw error
        }
    }

    public static func validate(data: Data, file: String = "refract.json") -> Result<Mapping, MappingError> {
        do {
            let document = try MappingJSONDocument(data: data, file: file)
            let validator = MappingValidator(document: document)
            validator.validate()
            guard validator.diagnostics.isEmpty else { return .failure(MappingError(diagnostics: validator.diagnostics)) }
            return .success(try JSONDecoder().decode(Mapping.self, from: data))
        } catch let error as MappingError {
            return .failure(MappingError(diagnostics: error.diagnostics.map {
                $0.code == "mappingSyntax" ? Diagnostic(code: "mapping.invalid_json", message: $0.message,
                    suggestion: $0.suggestion, location: $0.location) : $0
            }))
        } catch {
            return .failure(MappingError(diagnostics: [Diagnostic(code: "mappingType",
                message: "The validated mapping cannot be decoded.",
                suggestion: "Report this mapping schema inconsistency with a minimal input.",
                location: SourceLocation(file: file, line: 1, column: 1))]))
        }
    }

    public func platform(_ target: Platform) -> PlatformMapping {
        target == .android ? android : harmonyOS
    }

    public func component(named name: String, native: Bool = false, platform: Platform,
                          location: SourceLocation? = nil) throws -> Component {
        let registry = self.platform(platform)
        if let component = (native ? registry.nativeComponents : registry.components)[name] { return component }
        throw Diagnostic(code: native ? "missingNativeMapping" : "missingComponentMapping",
            message: "The \(native ? "native component" : "component") `\(name)` has no \(platform.displayName) mapping.",
            suggestion: "Declare its typed target in `\(platform.rawValue).\(native ? "nativeComponents" : "components").\(name)`.",
            location: location)
    }

    public func token(_ key: String, category: TokenCategory, platform: Platform,
                      location: SourceLocation? = nil) throws -> String {
        if let value = self.platform(platform).tokens[category][key] { return value }
        throw Diagnostic(code: "missingTokenMapping",
            message: "The \(category.rawValue) token `\(key)` has no \(platform.displayName) mapping.",
            suggestion: "Declare it in `\(platform.rawValue).tokens.\(category.rawValue)` with a typed native reference.",
            location: location)
    }

    public func stringResource(_ key: String, platform: Platform,
                               location: SourceLocation? = nil) throws -> Resource {
        let resources = self.platform(platform).resources
        guard resources.isConfigured else {
            throw Diagnostic(code: "R.string.not_configured",
                message: "The \(platform.displayName) string resource catalog is not configured.",
                suggestion: "Declare the platform's resource table in refract.json.", location: location)
        }
        guard Self.isResourceKey(key) else {
            throw Diagnostic(code: "R.string.invalid_key",
                message: "The string key `\(key)` is not a lowercase dot-separated resource key.",
                suggestion: "Use lowercase ASCII letters and digits in nonempty dot-separated segments.",
                location: location)
        }
        guard let name = resources.strings[key] else {
            throw Diagnostic(code: platform == .android ? "R.string.missing_android" : "R.string.missing_harmony",
                message: "The string key `\(key)` has no \(platform.displayName) resource mapping.",
                suggestion: "Declare `\(key.replacingOccurrences(of: ".", with: "_"))` in `\(platform.rawValue).resources.strings`.",
                location: location)
        }
        guard name == key.replacingOccurrences(of: ".", with: "_") else {
            throw Diagnostic(code: "R.string.invalid_resource",
                message: "The resource name `\(name)` does not match the normalized key `\(key)`.",
                suggestion: "Use `\(key.replacingOccurrences(of: ".", with: "_"))` on both platforms.",
                location: location)
        }
        return Resource(key: key, nativeName: name, className: resources.className,
                        namespace: resources.namespace, table: resources.stringTable)
    }

    static func isResourceKey(_ key: String) -> Bool {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) } }
    }
}

public struct MappingError: Error, Equatable, Sendable, CustomStringConvertible {
    public let diagnostics: [Diagnostic]
    public init(diagnostics: [Diagnostic]) { self.diagnostics = diagnostics }
    public var description: String { diagnostics.map(\.rendered).joined(separator: "\n") }
}

public struct PlatformMapping: Codable, Equatable, Sendable {
    public var output: Output
    public var imports: [NativeImport]
    public var components: [String: Component]
    public var nativeComponents: [String: Component]
    public var modifiers: [String: ModifierSignature]
    public var tokens: TokenSet
    public var resources: Resources

    public init(output: Output = .unspecified, imports: [NativeImport] = [], components: [String: Component] = [:],
                nativeComponents: [String: Component] = [:], modifiers: [String: ModifierSignature] = [:],
                tokens: TokenSet = .empty, resources: Resources = .empty) {
        self.output = output
        self.imports = imports
        self.components = components
        self.nativeComponents = nativeComponents
        self.modifiers = modifiers
        self.tokens = tokens
        self.resources = resources
    }

    public static let empty = PlatformMapping()

    enum CodingKeys: String, CodingKey { case output, imports, components, nativeComponents, modifiers, tokens, resources }
}

public struct Output: Codable, Equatable, Sendable {
    public var directory: String
    public var packageName: String?
    public init(directory: String, packageName: String? = nil) {
        self.directory = directory
        self.packageName = packageName
    }
    public static let unspecified = Output(directory: "")
}

public struct NativeImport: Codable, Equatable, Sendable {
    public var module: String
    public var symbols: [String]

    private enum CodingKeys: String, CodingKey { case module, symbols }

    public init(module: String, symbols: [String]) {
        self.module = module
        self.symbols = symbols
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let symbol = try? container.decode(String.self) {
            module = symbol
            symbols = [symbol.split(separator: ".").last.map(String.init) ?? symbol]
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        module = try values.decode(String.self, forKey: .module)
        symbols = try values.decode([String].self, forKey: .symbols)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(module)
    }
}

public struct Component: Codable, Equatable, Sendable {
    public var parameters: [Parameter]
    public var content: ContentKind
    public var contentParameter: String?
    public var modifiers: [String]
    public var target: String
    public var argumentStyle: ArgumentStyle
    public var arguments: [ArgumentBinding]
    public var modifierParameter: String?
    public var attributes: [String: Attribute]
    /// The native interop compatibility form's imported module; canonical mappings use `imports`.
    public var module: String?
    public var kind: String?

    public init(parameters: [Parameter] = [], content: ContentKind = .none, contentParameter: String? = nil,
                modifiers: [String] = [], target: String, argumentStyle: ArgumentStyle = .named,
                arguments: [ArgumentBinding] = [], modifierParameter: String? = nil,
                attributes: [String: Attribute] = [:], module: String? = nil, kind: String? = nil) {
        self.parameters = parameters
        self.content = content
        self.contentParameter = contentParameter
        self.modifiers = modifiers
        self.target = target
        self.argumentStyle = argumentStyle
        self.arguments = arguments
        self.modifierParameter = modifierParameter
        self.attributes = attributes
        self.module = module
        self.kind = kind
    }

    public var hasContent: Bool { content != .none }
}

public struct Parameter: Codable, Equatable, Sendable {
    public var label: String
    public var type: ParameterType
    public var required: Bool

    public init(label: String, type: ParameterType, required: Bool = true) {
        self.label = label
        self.type = type
        self.required = required
    }
}

public enum ParameterType: String, Codable, CaseIterable, Sendable {
    case string, bool, int, double, length, color, font, image, stringKey
    case action, actionString, actionBool, actionInt, actionDouble

    public var isAction: Bool { rawValue.hasPrefix("action") }
}

public enum ContentKind: String, Codable, Sendable {
    case none, trailingClosure, parameter, builder
}

public enum ArgumentStyle: String, Codable, Sendable {
    case named, object, positional
}

public struct ArgumentBinding: Codable, Equatable, Sendable {
    public var source: String
    public var target: String?
    public init(source: String, target: String? = nil) {
        self.source = source
        self.target = target
    }
}

public struct Attribute: Codable, Equatable, Sendable {
    public var kind: AttributeKind
    public var target: String
    public var arguments: [ArgumentBinding]?
    public init(kind: AttributeKind, target: String, arguments: [ArgumentBinding]? = nil) {
        self.kind = kind
        self.target = target
        self.arguments = arguments
    }
}

public enum AttributeKind: String, Codable, Sendable { case parameter, chain }

public struct ModifierSignature: Codable, Equatable, Sendable {
    public var parameters: [Parameter]
    public init(parameters: [Parameter] = []) { self.parameters = parameters }
}

public struct TokenSet: Codable, Equatable, Sendable {
    public var spacing: [String: String]
    public var radius: [String: String]
    public var font: [String: String]
    public var color: [String: String]

    public init(spacing: [String: String] = [:], radius: [String: String] = [:],
                font: [String: String] = [:], color: [String: String] = [:]) {
        self.spacing = spacing
        self.radius = radius
        self.font = font
        self.color = color
    }

    public static let empty = TokenSet()
    public subscript(_ category: TokenCategory) -> [String: String] {
        switch category {
        case .spacing: spacing
        case .radius: radius
        case .font: font
        case .color: color
        }
    }
}

public enum TokenCategory: String, CaseIterable, Codable, Sendable {
    case spacing, radius, font, color
    public var parameterType: ParameterType {
        switch self {
        case .spacing, .radius: .length
        case .font: .font
        case .color: .color
        }
    }
}

public struct Resources: Codable, Equatable, Sendable {
    public var className: String?
    public var namespace: String?
    public var stringTable: String?
    public var strings: [String: String]

    public init(className: String? = nil, namespace: String? = nil, stringTable: String? = nil,
                strings: [String: String] = [:]) {
        self.className = className
        self.namespace = namespace
        self.stringTable = stringTable
        self.strings = strings
    }
    public static let empty = Resources()
    public var isConfigured: Bool { className != nil || stringTable != nil }
}

public struct Resource: Equatable, Sendable {
    public var key: String
    public var nativeName: String
    public var className: String?
    public var namespace: String?
    public var table: String?
}

private struct LegacyMapping: Decodable {
    struct Entry: Decodable {
        struct Target: Decodable {
            struct Argument: Decodable { let swift: String; let name: String; let type: String }
            let kind: String
            let symbol: String
            let module: String
            let parameters: [Argument]
        }
        let swift: String
        let android: Target
        let harmonyOS: Target
    }
    let version: Int
    let nativeComponents: [Entry]

    var mapping: Mapping {
        var android = PlatformMapping.empty
        var harmony = PlatformMapping.empty
        for entry in nativeComponents {
            let common = commonParameters(entry.android.parameters, entry.harmonyOS.parameters)
            android.nativeComponents[entry.swift] = convert(entry.android, parameters: common, style: .named)
            harmony.nativeComponents[entry.swift] = convert(entry.harmonyOS, parameters: common, style: .object)
        }
        return Mapping(android: android, harmonyOS: harmony)
    }

    private func commonParameters(_ android: [Entry.Target.Argument], _ harmony: [Entry.Target.Argument]) -> [Parameter] {
        zip(android, harmony).map { a, h in Parameter(label: a.swift, type: sourceType(a.type, h.type)) }
    }

    private func sourceType(_ android: String, _ harmony: String) -> ParameterType {
        switch (android, harmony) {
        case ("String", "string"): .string
        case ("Boolean", "boolean"): .bool
        case ("Int", "number"): .int
        case ("Double", "number"): .double
        default: .string // The legacy validator rejects this input before decoding.
        }
    }

    private func convert(_ target: Entry.Target, parameters: [Parameter], style: ArgumentStyle) -> Component {
        Component(parameters: parameters, target: target.symbol, argumentStyle: style,
                  arguments: target.parameters.map { ArgumentBinding(source: $0.swift, target: $0.name) },
                  module: target.module, kind: target.kind)
    }
}
