import Foundation
import RefractIR

/// A generator-only view of a project's configured native catalogs.
public struct StringResourceConfiguration: Sendable {
    public let androidPath: String
    public let harmonyPath: String
    public let baseURL: URL

    public init(androidPath: String, harmonyPath: String, baseURL: URL) {
        self.androidPath = androidPath
        self.harmonyPath = harmonyPath
        self.baseURL = baseURL
    }
}

extension Mapping {
    public func stringCatalog(_ text: LocalizedText, platform: Platform,
                              location: SourceLocation? = nil) throws -> StringResourceEntry {
        let resource = try stringResource(text.key, platform: platform, location: location)
        let configuration = self.platform(platform).resources
        guard let path = configuration.catalog else {
            throw Diagnostic(code: "R.string.not_configured",
                message: "The \(platform.displayName) native string catalog path is not configured.",
                suggestion: "Declare `resources.catalog` with the platform's base strings.xml or string.json path",
                location: location)
        }
        guard let baseURL = resourceBaseURL else {
            throw Diagnostic(code: "R.string.not_configured",
                message: "The native string catalog has no resolved mapping directory.",
                suggestion: "Load refract.json by path or provide an explicit resourceBaseURL for in-memory generation",
                location: location)
        }
        let url = StringResourceLoader.resolve(path, relativeTo: baseURL)
        let catalog = platform == .android
            ? try StringResourceLoader.loadAndroid(url)
            : try StringResourceLoader.loadHarmony(url)
        guard let entry = catalog[resource.nativeName] else {
            throw Diagnostic(code: platform == .android ? "R.string.missing_android" : "R.string.missing_harmony",
                message: "String key `\(text.key)` is declared in the mapping but absent as `\(resource.nativeName)` in the \(platform.displayName) catalog.",
                suggestion: "Add the resource to the platform's base string catalog",
                location: location)
        }
        let arguments = try text.arguments.map { try localizationArgumentType($0) }
        guard entry.format.arguments == arguments else {
            throw Diagnostic(code: "R.string.format_arguments",
                message: "String key `\(text.key)` expects [\(entry.format.arguments.map(\.rawValue).joined(separator: ", "))] in \(platform.displayName), but interpolation supplies [\(arguments.map(\.rawValue).joined(separator: ", "))].",
                suggestion: "Match one-based positional placeholders to the ordered String, Int and Double interpolation arguments",
                location: location)
        }
        return entry
    }

    private func localizationArgumentType(_ expression: RefractIR.Expression) throws -> ValueType {
        guard let type = expression.type, type != .bool else {
            throw Diagnostic(code: "R.string.interpolation",
                message: "A localization argument has no supported static String, Int or Double type.",
                suggestion: "Declare the interpolated screen input with an explicit supported type",
                location: expression.location)
        }
        return type
    }
}

public enum LocalizedTextEmitter {
    public static func compose(_ expression: RefractIR.Expression, mapping: Mapping,
                               packageName: String? = nil,
                               argument: (RefractIR.Expression) throws -> String) throws -> String {
        guard case let .localizedText(text) = expression.value else {
            throw unsupported(expression)
        }
        _ = try mapping.stringCatalog(text, platform: .android, location: expression.location)
        _ = try StringResourceName.make(key: text.key, location: expression.location)
        let resource = try mapping.stringResource(text.key, platform: .android, location: expression.location)
        let values = try text.arguments.map(argument)
        let reference = resource.className.map {
            $0 == packageName.map { "\($0).R" } ? "R.string.\(resource.nativeName)" : "\($0).string.\(resource.nativeName)"
        } ?? "R.string.\(resource.nativeName)"
        return "stringResource(\(([reference] + values).joined(separator: ", ")))"
    }

    public static func arkUI(_ expression: RefractIR.Expression, mapping: Mapping,
                             argument: (RefractIR.Expression) throws -> String) throws -> String {
        guard case let .localizedText(text) = expression.value else {
            throw unsupported(expression)
        }
        _ = try mapping.stringCatalog(text, platform: .harmonyOS, location: expression.location)
        _ = try StringResourceName.make(key: text.key, location: expression.location)
        let resource = try mapping.stringResource(text.key, platform: .harmonyOS, location: expression.location)
        let values = try text.arguments.map(argument)
        let table = resource.table ?? "string"
        let namespace = resource.namespace ?? "app"
        return "$r('\(namespace).\(table).\(resource.nativeName)'\((values.isEmpty ? "" : ", ") + values.joined(separator: ", ")))"
    }

    private static func unsupported(_ expression: RefractIR.Expression) -> Diagnostic {
        Diagnostic(code: "R.string.unsupported_expression",
                   message: "Text must be a resolved localized resource or explicit verbatim text.",
                   suggestion: "Use a static resource key, typed interpolation or Text(verbatim:)",
                   location: expression.location)
    }
}
