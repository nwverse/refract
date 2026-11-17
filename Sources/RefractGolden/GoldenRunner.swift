import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping

public struct GoldenResult: Sendable {
    public let kotlin: String?
    public let arkTS: String?
    public let diagnostics: [Diagnostic]
    public init(kotlin: String?, arkTS: String?, diagnostics: [Diagnostic]) {
        self.kotlin = kotlin
        self.arkTS = arkTS
        self.diagnostics = diagnostics
    }
    public var renderedDiagnostics: String { diagnostics.map { $0.rendered + "\n" }.joined() }
}

public enum GoldenRunner {
    public static func generate(_ fixture: FixtureCase) throws -> GoldenResult {
        var diagnostics = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input)).diagnostics
        let mapping: Mapping
        do {
            if let contents = fixture.mapping {
                mapping = try Mapping.load(data: Data(contents.utf8), file: "refract.json",
                                           resourceBaseURL: fixture.resourceBaseURL)
            } else { mapping = .empty }
        } catch let error as MappingError {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics + error.diagnostics)
        } catch let diagnostic as Diagnostic {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics + [diagnostic])
        }
        // A mapping diagnostic is evaluated even when Swift parsing also fails: source and project
        // configuration are independent errors, and both must be reported before generation is skipped.
        guard diagnostics.isEmpty || mapping != .empty else {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
        let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input), mapping: mapping)
        // When the mapping-aware pass also rejects the source, retain independent model-input
        // errors from the first pass. A successful mapped pass is the only valid source of truth.
        if unit.hasErrors || (!diagnostics.isEmpty && unit.module.screens.isEmpty) {
            // Without a mapping, a custom view is only a native-view candidate. Once the mapping-aware
            // pass classifies it as a component or a resource expression, that candidate is not an error.
            let nativeCandidates = mapping == .empty ? diagnostics : diagnostics.filter { $0.code != "RFNATIVE001" }
            var seen = Set(nativeCandidates)
            diagnostics = nativeCandidates + unit.diagnostics.filter { seen.insert($0).inserted }
        } else {
            diagnostics = unit.diagnostics
        }
        guard !unit.hasErrors, diagnostics.isEmpty else {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
        do {
            // Resolve every localized value before either backend emits. This catches a missing second-platform
            // resource instead of returning one successful output followed by a late backend error.
            try LocalizationResourceValidator.validate(module: unit.module, mapping: mapping)
            try AssetResourceValidator.validate(module: unit.module, mapping: mapping)
        } catch let diagnostic as Diagnostic {
            diagnostics.append(diagnostic)
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
        var kotlin: String?
        var ark: String?
        do { kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping) }
        catch let diagnostic as Diagnostic { diagnostics.append(diagnostic) }
        catch let group as DiagnosticGroup { diagnostics.append(contentsOf: group.diagnostics) }
        catch let error as InteropMappingError { diagnostics.append(contentsOf: error.diagnostics) }
        do { ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping) }
        catch let diagnostic as Diagnostic { diagnostics.append(diagnostic) }
        catch let group as DiagnosticGroup { diagnostics.append(contentsOf: group.diagnostics) }
        catch let error as InteropMappingError { diagnostics.append(contentsOf: error.diagnostics) }
        guard diagnostics.isEmpty else {
            var seen: Set<Diagnostic> = []
            return GoldenResult(kotlin: nil, arkTS: nil,
                                diagnostics: diagnostics.filter { seen.insert($0).inserted })
        }
        return GoldenResult(kotlin: kotlin, arkTS: ark, diagnostics: diagnostics)
    }

    /// Returns actionable mismatch descriptions instead of rewriting hand-authored expectations.
    public static func differences(for fixture: FixtureCase, result: GoldenResult) -> [String] {
        var differences: [String] = []
        let expected = fixture.expectedDiagnostics ?? ""
        if result.renderedDiagnostics != expected {
            differences.append("\(fixture.name): Expected.diagnostics differs.\nExpected:\n\(expected)\nActual:\n\(result.renderedDiagnostics)")
        }
        if let expected = fixture.expectedKotlin, result.kotlin != expected {
            differences.append("\(fixture.name): Expected.kt differs from regenerated Compose output.")
        }
        if let expected = fixture.expectedArkTS, result.arkTS != expected {
            differences.append("\(fixture.name): Expected.ets differs from regenerated ArkUI output.")
        }
        return differences
    }
}
