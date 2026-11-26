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
    /// Successful cross-file outputs, in explicit input order.
    public let additionalOutputs: [(source: String, kotlin: String, arkTS: String)]
    public init(kotlin: String?, arkTS: String?, diagnostics: [Diagnostic],
                additionalOutputs: [(source: String, kotlin: String, arkTS: String)] = []) {
        self.kotlin = kotlin
        self.arkTS = arkTS
        self.diagnostics = diagnostics
        self.additionalOutputs = additionalOutputs
    }
    public var renderedDiagnostics: String { diagnostics.map { $0.rendered + "\n" }.joined() }
}

public enum GoldenRunner {
    public static func generate(_ fixture: FixtureCase) throws -> GoldenResult {
        var diagnostics: [Diagnostic] = []
        if fixture.additionalInputs.isEmpty {
            diagnostics = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input)).diagnostics
        }
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
        if !fixture.additionalInputs.isEmpty {
            return try generateMultiple(fixture, mapping: mapping)
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

    private static func generateMultiple(_ fixture: FixtureCase, mapping: Mapping) throws -> GoldenResult {
        let sources = fixture.additionalInputs.keys.sorted().map {
            SourceFile(path: $0, contents: fixture.additionalInputs[$0] ?? "")
        }
        let units = Frontend.parse(sources: sources, mapping: mapping)
        var diagnostics = units.flatMap(\.diagnostics)
        guard !units.contains(where: \.hasErrors) else {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
        do {
            for unit in units {
                try LocalizationResourceValidator.validate(module: unit.module, mapping: mapping)
            }
        } catch let diagnostic as Diagnostic {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics + [diagnostic])
        }
        let nativeSources = NativeSourceSet(modules: units.map(\.module),
                                           models: units.flatMap(\.resolvedModels),
                                           itemTypes: units.flatMap(\.resolvedItemTypes))
        var outputs: [(source: String, kotlin: String, arkTS: String)] = []
        for unit in units {
            do {
                let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping,
                                                          sources: nativeSources)
                let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping,
                                                     sources: nativeSources)
                outputs.append((unit.module.sourceFile, kotlin, ark))
            } catch let diagnostic as Diagnostic {
                diagnostics.append(diagnostic)
            } catch let group as DiagnosticGroup {
                diagnostics.append(contentsOf: group.diagnostics)
            } catch let error as InteropMappingError {
                diagnostics.append(contentsOf: error.diagnostics)
            }
        }
        guard diagnostics.isEmpty else {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
        return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: [], additionalOutputs: outputs)
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
        if fixture.expectedDiagnostics != nil,
           result.kotlin != nil || result.arkTS != nil || !result.additionalOutputs.isEmpty {
            differences.append("\(fixture.name): A diagnostics-only case unexpectedly generated native output; record the diagnostic or provide both hand-reviewed native expectations.")
        }
        for expected in fixture.additionalOutputs {
            guard let actual = result.additionalOutputs.first(where: { $0.source == expected.source }) else {
                differences.append("\(fixture.name): Missing generated output for \(expected.source).")
                continue
            }
            if actual.kotlin != expected.kotlin {
                differences.append("\(fixture.name): Expected.\(expected.source).kt differs from regenerated Compose output.")
            }
            if actual.arkTS != expected.arkTS {
                differences.append("\(fixture.name): Expected.\(expected.source).ets differs from regenerated ArkUI output.")
            }
        }
        if result.additionalOutputs.count != fixture.additionalOutputs.count {
            differences.append("\(fixture.name): Unexpected generated file count.")
        }
        return differences
    }
}
