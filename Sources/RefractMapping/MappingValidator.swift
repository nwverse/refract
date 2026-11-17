import Foundation
import RefractIR

/// JSON Schema validation with stable, source-located diagnostics; no decoder heuristics or defaulting.
final class MappingValidator {
    typealias JSON = MappingJSONDocument.Value

    let document: MappingJSONDocument
    var diagnostics: [Diagnostic] = []
    var root: JSON { document.root }

    init(document: MappingJSONDocument) { self.document = document }

    func validate() {
        for duplicate in document.duplicates() {
            error("mappingDuplicateKey", "The JSON key `\(duplicate.key)` is duplicated at `\(duplicate.path)`.",
                  "Keep one `\(duplicate.key)` key and remove the duplicate.", at: duplicate.location)
        }
        if root.property("version") != nil { validateLegacy(); return }
        guard let version = field("schemaVersion", in: root, required: true) else { return }
        guard integer(version) == 1 else {
            error("mappingVersion", "The schema version \(version.number ?? version.string ?? "unknown") is not supported.",
                  "Use schema version 1.", at: version.location)
            return
        }
        fields(root, allowed: ["schemaVersion", "android", "harmonyOS"])
        guard let android = field("android", in: root, required: true),
              let harmony = field("harmonyOS", in: root, required: true) else { return }
        platform(android, .android)
        platform(harmony, .harmonyOS)
        modifierBindings(android)
        modifierBindings(harmony)
        comparePlatforms(android, harmony)
    }

    private func platform(_ value: JSON, _ platform: Platform) {
        fields(value, allowed: ["output", "imports", "components", "nativeComponents", "modifiers", "tokens", "resources", "symbols", "minimumAPI"])
        output(field("output", in: value, required: true), platform)
        imports(field("imports", in: value, required: true), platform)
        components(field("components", in: value, required: true), "components")
        components(field("nativeComponents", in: value, required: true), "nativeComponents")
        modifiers(field("modifiers", in: value, required: true))
        tokens(field("tokens", in: value, required: true))
        symbols(field("symbols", in: value), platform)
        resources(field("resources", in: value, required: true), platform)
        if let minimum = field("minimumAPI", in: value), integer(minimum) == nil || (integer(minimum) ?? 0) < 12 {
            error("mappingMinimumAPI", "minimumAPI must be an integer SDK/API level of at least 12.",
                  "Declare the minimum level supported by the consuming native application.", at: minimum.location)
        }
    }

    private func output(_ value: JSON?, _ platform: Platform) {
        guard let value, object(value, "an output configuration") else { return }
        fields(value, allowed: ["directory", "packageName"])
        if let directory = field("directory", in: value, required: true), let text = string(directory) {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            if text.isEmpty || text.hasPrefix("/") || text.hasSuffix("/") || text.contains("\\") || text.contains("\0")
                || parts.contains(".") || parts.contains("..") || parts.contains("") {
                error("mappingOutput", "The output directory `\(text)` is not a normalized relative POSIX path.",
                      "Use a nonempty relative path without '.', '..', backslashes or a trailing slash.", at: directory.location)
            }
        }
        if platform == .android {
            if let package = field("packageName", in: value, required: true) {
                pattern(package, "^[a-z_][a-z0-9_]*(\\.[a-z_][a-z0-9_]*)*$", "an Android package name", code: "mappingOutput")
            }
        } else if let package = field("packageName", in: value) {
            error("mappingUnknownKey", "HarmonyOS output cannot declare `packageName`.",
                  "Use only `directory` for HarmonyOS output.", at: package.location)
        }
    }

    private func imports(_ value: JSON?, _ platform: Platform) {
        guard let value, let values = array(value) else { return }
        var seen: Set<String> = []
        for item in values {
            if platform == .android {
                guard let text = string(item) else { continue }
                if !matches(text, Self.referencePattern) {
                    error("mappingImport", "The Android import `\(text)` is not a qualified symbol.",
                          "Use a fully qualified Kotlin symbol.", at: item.location)
                }
                if !seen.insert(text).inserted {
                    error("mappingImport", "The Android import `\(text)` is duplicated.",
                          "Keep one copy of the import.", at: item.location)
                }
            } else {
                guard object(item, "a HarmonyOS import") else { continue }
                fields(item, allowed: ["module", "symbols"])
                if let module = field("module", in: item, required: true), let text = string(module) {
                    if text.isEmpty || text.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" || $0 == "\\" }) {
                        error("mappingImport", "The HarmonyOS module `\(text)` is not a safe module reference.",
                              "Use a module specifier without whitespace, quotes or backslashes.", at: module.location)
                    }
                    if !seen.insert(text).inserted {
                        error("mappingImport", "The HarmonyOS module `\(text)` is imported more than once.",
                              "Combine its symbols into one import declaration.", at: module.location)
                    }
                }
                guard let symbols = field("symbols", in: item, required: true), let values = array(symbols) else { continue }
                if values.isEmpty {
                    error("mappingImport", "A HarmonyOS import must name at least one symbol.",
                          "Add an explicit imported symbol.", at: symbols.location)
                }
                var names: Set<String> = []
                for symbol in values {
                    identifier(symbol, code: "mappingImport")
                    if let name = symbol.string, !names.insert(name).inserted {
                        error("mappingImport", "The imported symbol `\(name)` is duplicated in this module.",
                              "Keep one copy of the symbol.", at: symbol.location)
                    }
                }
            }
        }
    }

    private func components(_ value: JSON?, _ kind: String) {
        guard let value, object(value, "a component registry") else { return }
        for (name, component, _) in value.object ?? [] {
            if !matches(name, "^[A-Z][A-Za-z0-9_]*$") {
                error("mappingValue", "The component name `\(name)` is not an UpperCamelCase identifier.",
                      "Use the Swift component type name.", at: component.location)
            }
            guard object(component, "a component mapping") else { continue }
            fields(component, allowed: ["parameters", "content", "contentParameter", "modifiers", "target",
                                       "argumentStyle", "arguments", "modifierParameter", "attributes", "kind", "module"])
            parameters(field("parameters", in: component, required: true), component)
            identifier(field("target", in: component, required: true))
            if let style = field("argumentStyle", in: component, required: true) {
                enumeration(style, ["named", "object", "positional"])
            }
            let content = field("content", in: component, required: true).flatMap {
                enumeration($0, ["none", "trailingClosure", "parameter", "builder"])
            }
            if content == "parameter" {
                identifier(field("contentParameter", in: component, required: true))
            } else if let extra = field("contentParameter", in: component) {
                error("mappingContent", "`contentParameter` is only valid when content is `parameter`.",
                      "Remove it or select parameter content.", at: extra.location)
            }
            if let modifiers = field("modifiers", in: component, required: true), let values = array(modifiers) {
                var names: Set<String> = []
                for modifier in values {
                    identifier(modifier)
                    if let name = modifier.string, !names.insert(name).inserted {
                        error("mappingModifier", "The modifier `\(name)` is declared twice.",
                              "Keep one modifier declaration.", at: modifier.location)
                    }
                }
            }
            guard let style = field("argumentStyle", in: component, required: true).flatMap({
                enumeration($0, ["named", "object", "positional"])
            }) else { continue }
            arguments(field("arguments", in: component, required: true), component, style, content: false)
            attributes(field("attributes", in: component, required: true), component)
            if let modifier = field("modifierParameter", in: component) { identifier(modifier) }
        }
    }

    private func parameters(_ value: JSON?, _ owner: JSON) {
        guard let value, let values = array(value) else { return }
        if values.count > 64 {
            error("mappingValue", "A component cannot declare more than 64 parameters.",
                  "Split the interface into supported components.", at: value.location)
        }
        var seen: Set<String> = []
        for parameter in values {
            guard object(parameter, "a parameter declaration") else { continue }
            fields(parameter, allowed: ["label", "type", "required"])
            guard let label = field("label", in: parameter, required: true), let text = string(label) else { continue }
            pattern(label, "^(_|[A-Za-z_][A-Za-z0-9_]*)*$", "a Swift external argument label")
            if !seen.insert(text).inserted {
                error("mappingParameter", "The parameter label `\(text)` is declared twice.",
                      "Use each Swift argument label once.", at: label.location)
            }
            if let type = field("type", in: parameter, required: true) {
                enumeration(type, ParameterType.allCases.map(\.rawValue))
            }
            if let required = field("required", in: parameter, required: true), required.bool == nil {
                typeError(required, "a boolean")
            }
        }
    }

    private func arguments(_ value: JSON?, _ component: JSON, _ style: String?, content: Bool) {
        guard let value, let values = array(value) else { return }
        if style == "positional", values.isEmpty, !content {
            error("mappingParameter", "A positional component needs an ordered argument list unless it only has children.",
                  "Declare source arguments in native call order.", at: value.location)
        }
        let parameters = parameterValues(component)
        var seen: Set<String> = []
        for argument in values {
            guard object(argument, "an argument binding") else { continue }
            fields(argument, allowed: ["source", "target"])
            guard let source = field("source", in: argument, required: true), let label = string(source) else { continue }
            if parameters[label] == nil {
                error("mappingParameter", "The target argument refers to unknown source label `\(label)`.",
                      "Declare the source parameter before binding it.", at: source.location)
            }
            if !seen.insert(label).inserted {
                error("mappingParameter", "The source label `\(label)` is bound more than once.",
                      "Bind each source argument exactly once.", at: source.location)
            }
            if style == "positional" {
                if let target = field("target", in: argument) {
                    error("mappingParameter", "Positional argument `\(label)` cannot declare a target label.",
                          "Remove `target` and use the declared order.", at: target.location)
                }
            } else if let target = field("target", in: argument, required: true) {
                identifier(target)
            }
            if parameters[label]?.type.isAction == true && content {
                error("mappingParameter", "An action cannot be used as a modifier value.",
                      "Bind an action only to a component callback parameter.", at: source.location)
            }
        }
        for (label, parameter) in parameters where parameter.required && !seen.contains(label) {
            error("mappingParameter", "The required source parameter `\(label)` has no target binding.",
                  "Bind it in `arguments` or make it optional when the native default preserves its semantics.",
                  at: value.location)
        }
    }

    private func attributes(_ value: JSON?, _ component: JSON) {
        guard let value, object(value, "a modifier attribute registry") else { return }
        let accepted = Set(field("modifiers", in: component)?.array?.compactMap(\.string) ?? [])
        for (name, attribute, _) in value.object ?? [] {
            if !accepted.contains(name) {
                error("mappingModifier", "The modifier `\(name)` has an attribute binding but is not accepted by this component.",
                      "Declare it in the component's `modifiers` array.", at: attribute.location)
            }
            guard object(attribute, "a modifier attribute") else { continue }
            fields(attribute, allowed: ["kind", "target", "arguments"])
            identifier(field("target", in: attribute, required: true))
            guard let kind = field("kind", in: attribute, required: true).flatMap({ enumeration($0, ["parameter", "chain"]) }) else { continue }
            if kind == "chain" {
                // Chain arguments are validated against the modifier registry after both registries are read.
            } else if let arguments = field("arguments", in: attribute) {
                error("mappingModifier", "A parameter attribute cannot have chain arguments.",
                      "Use `kind: chain` when forwarding modifier arguments.", at: arguments.location)
            }
        }
        for modifier in accepted where value.property(modifier) == nil {
            error("mappingModifier", "The accepted modifier `\(modifier)` has no attribute binding.",
                  "Declare its `parameter` or `chain` lowering in `attributes`.", at: value.location)
        }
    }

    private func modifiers(_ value: JSON?) {
        guard let value, object(value, "a modifier registry") else { return }
        for (_, modifier, _) in value.object ?? [] {
            guard object(modifier, "a modifier signature") else { continue }
            fields(modifier, allowed: ["parameters"])
            parameters(field("parameters", in: modifier, required: true), modifier)
        }
    }

    private func tokens(_ value: JSON?) {
        guard let value, object(value, "a token registry") else { return }
        fields(value, allowed: TokenCategory.allCases.map(\.rawValue))
        var keys: [String: String] = [:]
        for category in TokenCategory.allCases {
            guard let table = field(category.rawValue, in: value, required: true), object(table, "a token table") else { continue }
            for (key, reference, _) in table.object ?? [] {
                if !matches(key, "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$") {
                    error("mappingToken", "The token key `\(key)` is not a qualified source reference.",
                          "Use a reference such as `DesignSpacing.medium`.", at: reference.location)
                }
                if let previous = keys[key], previous != category.rawValue {
                    error("mappingToken", "The token key `\(key)` occurs in both `\(previous)` and `\(category.rawValue)`.",
                          "Use one token category for this key.", at: reference.location)
                }
                keys[key] = category.rawValue
                pattern(reference, Self.referencePattern, "a qualified native token reference", code: "mappingToken")
            }
        }
    }

    private func symbols(_ value: JSON?, _ platform: Platform) {
        guard let value, object(value, "a system-symbol registry") else { return }
        for (key, symbol, _) in value.object ?? [] {
            if !matches(key, "^[A-Za-z_][A-Za-z0-9_]*$") {
                error("mappingValue", "System symbol `\(key)` is not a supported identifier.",
                      "Use a declared SF Symbol name such as `gear` or `person`.", at: symbol.location)
            }
            fields(symbol, allowed: ["kind", "name"])
            guard let kind = field("kind", in: symbol, required: true)?.string else { continue }
            if platform == .android && kind == "media" || platform == .harmonyOS && kind != "media" {
                error("mappingPlatformMismatch", "The symbol kind `\(kind)` is invalid for this platform.",
                      "Use materialIcon or drawable for Android and media for HarmonyOS.", at: symbol.location)
            }
            if !["materialIcon", "drawable", "media"].contains(kind) {
                error("mappingValue", "The symbol kind `\(kind)` is unsupported.",
                      "Use materialIcon, drawable or media.", at: symbol.location)
            }
            pattern(field("name", in: symbol, required: true), Self.referencePattern,
                    "a typed native symbol or media resource", code: "mappingValue")
        }
    }

    private func resources(_ value: JSON?, _ platform: Platform) {
        guard let value, object(value, "a resource catalog") else { return }
        fields(value, allowed: platform == .android ? ["className", "catalog", "strings"] : ["namespace", "stringTable", "catalog", "strings"])
        if let catalog = field("catalog", in: value) {
            pattern(catalog, "^[^\\\\]+$", "a native base string catalog path", code: "mappingResource")
        }
        if platform == .android {
            pattern(field("className", in: value, required: true), "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+\\.R$",
                    "the application's fully qualified R class", code: "mappingResource")
        } else {
            identifier(field("namespace", in: value, required: true), code: "mappingResource")
            identifier(field("stringTable", in: value, required: true), code: "mappingResource")
        }
        guard let strings = field("strings", in: value, required: true), object(strings, "a string resource table") else { return }
        var names: [String: String] = [:]
        for (key, resource, _) in strings.object ?? [] {
            if !Mapping.isResourceKey(key) {
                error("mappingResource", "The string key `\(key)` is not a lowercase dot-separated key.",
                      "Use lowercase ASCII letters and digits in nonempty dot-separated segments.", at: resource.location)
            }
            let normalized = key.replacingOccurrences(of: ".", with: "_")
            guard let name = string(resource) else { continue }
            if name != normalized {
                error("mappingResource", "The resource name `\(name)` does not match normalized key `\(normalized)`.",
                      "Use `\(normalized)` for this key on both platforms.", at: resource.location)
            }
            if let other = names[name], other != key {
                error("mappingResource", "The resource name `\(name)` is shared by `\(other)` and `\(key)`.",
                      "Use one native resource per source key.", at: resource.location)
            }
            names[name] = key
        }
    }

    private func modifierBindings(_ platform: JSON) {
        let signatures = platform.property("modifiers")
        for registry in ["components", "nativeComponents"] {
            for (name, component, _) in platform.property(registry)?.object ?? [] {
                let accepted = Set(component.property("modifiers")?.array?.compactMap(\.string) ?? [])
                for modifier in accepted where signatures?.property(modifier) == nil {
                    error("mappingModifier", "The component `\(name)` accepts undeclared modifier `\(modifier)`.",
                          "Declare its typed signature in the platform `modifiers` registry.", at: component.location)
                }
                for (modifier, attribute, _) in component.property("attributes")?.object ?? [] {
                    guard attribute.property("kind")?.string == "chain", let signature = signatures?.property(modifier) else { continue }
                    arguments(attribute.property("arguments"), signature, "positional", content: true)
                }
            }
        }
    }

    private func comparePlatforms(_ android: JSON, _ harmony: JSON) {
        for registry in ["components", "nativeComponents"] {
            guard let a = android.property(registry)?.object, let h = harmony.property(registry)?.object else { continue }
            let b = Dictionary(h.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
            for (name, component, _) in a {
                guard let other = b[name] else {
                    error("mappingPlatformMismatch", "The \(registry) entry `\(name)` has no HarmonyOS counterpart.",
                          "Declare the same interface on both platforms.", at: component.location)
                    continue
                }
                compareParameters(field("parameters", in: component), field("parameters", in: other), name, registry)
                let ac = component.property("content")?.string
                let hc = other.property("content")?.string
                if (ac == "none") != (hc == "none") {
                    error("mappingContent", "The component `\(name)` supports children on only one platform.",
                          "Use content-capable native components on both platforms.", at: other.location)
                }
                let am = component.property("modifiers")?.array?.compactMap(\.string) ?? []
                let hm = other.property("modifiers")?.array?.compactMap(\.string) ?? []
                if am != hm {
                    error("mappingPlatformMismatch", "The component `\(name)` has different supported modifiers on the two platforms.",
                          "Use the same ordered source modifier list on both platforms.", at: other.property("modifiers")?.location)
                }
            }
            for (name, component, _) in h where !a.contains(where: { $0.0 == name }) {
                error("mappingPlatformMismatch", "The \(registry) entry `\(name)` has no Android counterpart.",
                      "Declare the same interface on both platforms.", at: component.location)
            }
        }
        compareModifierSignatures(android.property("modifiers"), harmony.property("modifiers"))
        let androidSymbols = Set(android.property("symbols")?.object?.map { $0.0 } ?? [])
        let harmonySymbols = Set(harmony.property("symbols")?.object?.map { $0.0 } ?? [])
        for key in androidSymbols.symmetricDifference(harmonySymbols).sorted() {
            error("mappingPlatformMismatch", "System symbol `\(key)` is missing on one platform.",
                  "Declare a typed native mapping for every source symbol on both platforms.",
                  at: (androidSymbols.contains(key) ? harmony : android).location)
        }
        for category in TokenCategory.allCases {
            let a = Set(android.property("tokens")?.property(category.rawValue)?.object?.map { $0.0 } ?? [])
            let h = Set(harmony.property("tokens")?.property(category.rawValue)?.object?.map { $0.0 } ?? [])
            for key in a.symmetricDifference(h).sorted() {
                error("mappingPlatformMismatch", "The \(category.rawValue) token `\(key)` is missing on one platform.",
                      "Declare the same source token on both platforms.", at: (a.contains(key) ? harmony : android).location)
            }
        }
        let a = android.property("resources")?.property("strings")?.object ?? []
        let h = harmony.property("resources")?.property("strings")?.object ?? []
        let hb = Dictionary(h.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        for (key, resource, _) in a {
            guard let other = hb[key] else {
                error("mappingPlatformMismatch", "The string key `\(key)` has no HarmonyOS resource declaration.",
                      "Declare the same key and normalized name on both platforms.", at: resource.location)
                continue
            }
            if resource.string != other.string {
                error("mappingPlatformMismatch", "The string key `\(key)` has different normalized names on the two platforms.",
                      "Use `\(key.replacingOccurrences(of: ".", with: "_"))` on both platforms.", at: other.location)
            }
        }
        for (key, resource, _) in h where !a.contains(where: { $0.0 == key }) {
            error("mappingPlatformMismatch", "The string key `\(key)` has no Android resource declaration.",
                  "Declare the same key and normalized name on both platforms.", at: resource.location)
        }
    }

    private func compareParameters(_ a: JSON?, _ b: JSON?, _ name: String, _ registry: String) {
        guard let a = a?.array, let b = b?.array else { return }
        guard a.count == b.count else {
            error("mappingPlatformMismatch", "The \(registry) entry `\(name)` has different parameter counts on the two platforms.",
                  "Declare the same ordered source parameters on both platforms.", at: b.first?.location)
            return
        }
        for (left, right) in zip(a, b) {
            let label = left.property("label")?.string ?? "<unknown>"
            let pairs = [("label", left.property("label")?.string, right.property("label")?.string),
                         ("type", left.property("type")?.string, right.property("type")?.string)]
            for (field, av, bv) in pairs where av != bv {
                error("mappingPlatformMismatch",
                      "The \(registry == "components" ? "component" : registry) `\(name)` parameter `\(label)` has different \(field)s on Android and HarmonyOS (`\(av ?? "missing")` and `\(bv ?? "missing")`).",
                      "Use the same \(field) on both platforms.", at: right.property(field)?.location ?? right.location)
            }
            if left.property("required")?.bool != right.property("required")?.bool {
                error("mappingPlatformMismatch", "The \(registry) entry `\(name)` parameter `\(label)` has different requiredness.",
                      "Use the same required flag on both platforms.", at: right.property("required")?.location)
            }
        }
    }

    private func compareModifierSignatures(_ a: JSON?, _ b: JSON?) {
        guard let a = a?.object, let b = b?.object else { return }
        let bb = Dictionary(b.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        for (name, modifier, _) in a {
            guard let other = bb[name] else {
                error("mappingPlatformMismatch", "The modifier `\(name)` has no HarmonyOS signature.",
                      "Declare the same source modifiers on both platforms.", at: modifier.location)
                continue
            }
            compareParameters(field("parameters", in: modifier), field("parameters", in: other), name, "modifier")
        }
        for (name, modifier, _) in b where !a.contains(where: { $0.0 == name }) {
            error("mappingPlatformMismatch", "The modifier `\(name)` has no Android signature.",
                  "Declare the same source modifiers on both platforms.", at: modifier.location)
        }
    }

    // #7's already published native-only draft is a distinct, explicitly versioned compatibility input.
    private func validateLegacy() {
        fields(root, allowed: ["version", "nativeComponents"])
        guard let version = field("version", in: root, required: true), integer(version) == 1 else {
            error("mappingVersion", "The native mapping draft must use version 1.",
                  "Use version 1 or migrate to the full schemaVersion 1 mapping.", at: root.location)
            return
        }
        guard let components = field("nativeComponents", in: root, required: true), let entries = array(components) else { return }
        for entry in entries {
            guard object(entry, "a native component declaration") else { continue }
            fields(entry, allowed: ["swift", "android", "harmonyOS"])
            let name = field("swift", in: entry, required: true).flatMap { string($0) } ?? "<unknown>"
            var parameters: [(String, String, String)] = []
            for platform in Platform.allCases {
                guard let target = field(platform.rawValue, in: entry, required: true), object(target, "a native target") else { continue }
                fields(target, allowed: ["kind", "symbol", "module", "parameters"])
                let expectedKind = platform == .android ? "composable" : "component"
                if let kind = field("kind", in: target, required: true) { enumeration(kind, [expectedKind]) }
                identifier(field("symbol", in: target, required: true))
                if let module = field("module", in: target, required: true), let text = string(module), !matches(text, Self.referencePattern) {
                    error("mappingImport", "The native module `\(text)` is not a qualified identifier.",
                          "Use an explicit module name.", at: module.location)
                }
                guard let values = field("parameters", in: target, required: true), let arguments = array(values) else { continue }
                var labels: Set<String> = []
                var current: [(String, String, String)] = []
                for argument in arguments {
                    guard object(argument, "a native target parameter") else { continue }
                    fields(argument, allowed: ["swift", "name", "type"])
                    guard let label = field("swift", in: argument, required: true), let source = string(label) else { continue }
                    identifier(field("name", in: argument, required: true))
                    let type = field("type", in: argument, required: true).flatMap { string($0) } ?? ""
                    let accepted = platform == .android ? ["String", "Boolean", "Int", "Double"] : ["string", "boolean", "number"]
                    if !accepted.contains(type) {
                        error("mappingParameter", "The native type `\(type)` is unsupported for `\(source)`.",
                              "Use the target type paired with String, Bool, Int or Double.", at: argument.property("type")?.location)
                    }
                    if !labels.insert(source).inserted {
                        error("mappingParameter", "The native parameter `\(source)` is duplicated.",
                              "Match the stored-property signature exactly once.", at: label.location)
                    }
                    current.append((source, type, argument.property("name")?.string ?? ""))
                }
                if platform == .android { parameters = current }
                else {
                    guard parameters.count == current.count else {
                        error("mappingPlatformMismatch", "The native component `\(name)` has different parameter counts.",
                              "Match the stored-property signature on both platforms.", at: values.location)
                        continue
                    }
                    for (a, h) in zip(parameters, current) {
                        let pair = (a.1, h.1)
                        let compatible = a.0 == h.0 && [("String", "string"), ("Boolean", "boolean"), ("Int", "number"), ("Double", "number")].contains { $0 == pair }
                        if !compatible {
                            error("mappingPlatformMismatch", "The native component `\(name)` parameter `\(a.0)` has incompatible target declarations.",
                                  "Use the same label and a supported String/Bool/Int/Double target-type pair.", at: values.location)
                        }
                    }
                }
            }
        }
    }

    private func parameterValues(_ component: JSON) -> [String: (type: ParameterType, required: Bool)] {
        var result: [String: (type: ParameterType, required: Bool)] = [:]
        for parameter in component.property("parameters")?.array ?? [] {
            guard let label = parameter.property("label")?.string,
                  let type = parameter.property("type")?.string.flatMap(ParameterType.init(rawValue:)) else { continue }
            result[label] = (type, parameter.property("required")?.bool ?? false)
        }
        return result
    }

    private func fields(_ value: JSON, allowed: [String]) {
        guard object(value, "an object") else { return }
        for (key, child, _) in value.object ?? [] where !allowed.contains(key) {
            error("mappingUnknownKey", "The key `\(key)` is not allowed in this mapping object.",
                  "Use the published refract.schema.json fields.", at: child.location)
        }
    }

    @discardableResult
    private func field(_ name: String, in value: JSON, required: Bool = false) -> JSON? {
        if let value = value.property(name) { return value }
        if required {
            error("mappingRequired", "The required key `\(name)` is missing.",
                  "Add `\(name)` to this mapping object.", at: value.location)
        }
        return nil
    }

    @discardableResult
    private func object(_ value: JSON, _ expected: String) -> Bool {
        guard value.object != nil else { typeError(value, expected); return false }
        return true
    }

    private func array(_ value: JSON) -> [JSON]? {
        guard let array = value.array else { typeError(value, "an array"); return nil }
        return array
    }

    private func string(_ value: JSON) -> String? {
        guard let string = value.string else { typeError(value, "a string"); return nil }
        return string
    }

    private func integer(_ value: JSON) -> Int? {
        guard let number = value.number, let integer = Int(number) else {
            typeError(value, "an integer schema version"); return nil
        }
        return integer
    }

    private func identifier(_ value: JSON?, code: String = "mappingValue") {
        pattern(value, "^[A-Za-z_][A-Za-z0-9_]*$", "an identifier", code: code)
    }

    private func pattern(_ value: JSON?, _ regex: String, _ expected: String, code: String = "mappingValue") {
        guard let value, let text = string(value) else { return }
        if !matches(text, regex) {
            error(code, "The value `\(text)` is not \(expected).",
                  "Use the syntax documented for this mapping field.", at: value.location)
        }
    }

    @discardableResult
    private func enumeration(_ value: JSON, _ values: [String]) -> String? {
        guard let text = string(value) else { return nil }
        if !values.contains(text) {
            error("mappingValue", "The value `\(text)` is not one of \(values.map { "`\($0)`" }.joined(separator: ", ")).",
                  "Use one of the declared enum values.", at: value.location)
            return nil
        }
        return text
    }

    private func typeError(_ value: JSON, _ expected: String) {
        error("mappingType", "Expected \(expected), found \(value.typeName).",
              "Use the JSON type required by refract.schema.json.", at: value.location)
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static let referencePattern = "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$"

    private func error(_ code: String, _ message: String, _ suggestion: String, at location: SourceLocation?) {
        diagnostics.append(Diagnostic(code: code, message: message, suggestion: suggestion, location: location))
    }
}
