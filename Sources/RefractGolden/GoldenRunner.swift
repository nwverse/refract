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
        let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input))
        var diagnostics = unit.diagnostics
        let mapping: Mapping
        do {
            if let contents = fixture.mapping {
                mapping = try Mapping.load(data: Data(contents.utf8), file: "refract.json")
            } else { mapping = .empty }
        } catch let diagnostic as Diagnostic {
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics + [diagnostic])
        }
        // A mapping diagnostic is evaluated even when Swift parsing also fails: source and project
        // configuration are independent errors, and both must be reported before generation is skipped.
        guard !unit.hasErrors else { return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics) }
        do {
            let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
            let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
            return GoldenResult(kotlin: kotlin, arkTS: ark, diagnostics: diagnostics)
        } catch let diagnostic as Diagnostic {
            diagnostics.append(diagnostic)
            return GoldenResult(kotlin: nil, arkTS: nil, diagnostics: diagnostics)
        }
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
