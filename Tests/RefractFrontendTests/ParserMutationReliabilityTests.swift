import Testing
@testable import RefractFrontend
import RefractIR

private struct FixedSeedGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private let mutationSource = """
import SwiftUI

protocol SettingsModel: RefractModel {
    var title: String { get }
    func save()
}

struct Settings: View {
    let model: SettingsModel
    var body: some View {
        VStack {
            Text(model.title)
            Button("settings.save") { model.save() }
        }
    }
}
"""

@Suite("Bounded parser mutation differential")
struct ParserMutationReliabilityTests {
    @Test func malformedSourcesNeverBecomeNativeIR() {
        var random = FixedSeedGenerator(seed: 0x160)
        let characters = Array(mutationSource)
        let replacements: [Character] = ["{", "}", "(", ")", "\"", ":", ";", "\\", "[", "]", "\n"]
        // Each case changes one to four scalar positions in a source shorter than 400 characters.
        for iteration in 0..<256 {
            var mutated = characters
            for _ in 0..<Int.random(in: 1...4, using: &random) {
                let index = Int.random(in: mutated.indices, using: &random)
                switch Int.random(in: 0..<3, using: &random) {
                case 0: mutated.remove(at: index)
                case 1: mutated[index] = replacements.randomElement(using: &random)!
                default: mutated.insert(replacements.randomElement(using: &random)!, at: index)
                }
            }
            let source = String(mutated)
            let reference = Frontend.parse(SourceFile(path: "Mutation.swift", contents: source))
            for _ in 0..<2 {
                let repeated = Frontend.parse(SourceFile(path: "Mutation.swift", contents: source))
                #expect(repeated == reference, "Parse differs at mutation iteration \(iteration)")
            }
            #expect(reference.diagnostics.allSatisfy {
                $0.location?.file == "Mutation.swift" && ($0.location?.line ?? 0) > 0
                    && ($0.location?.column ?? 0) > 0
            }, "Missing source coordinate at mutation iteration \(iteration)")
            #expect(reference.module.sourceFile == "Mutation.swift")
            #expect(reference.module.screens.allSatisfy { screen in
                // A rejected or unrelated declaration must not become a partial native component.
                !containsUnsupportedNode(screen.body)
            }, "Unexpected partial screen at mutation iteration \(iteration)")
            if reference.hasErrors {
                #expect(!reference.diagnostics.isEmpty)
            }
            // A syntactically valid edit can remove a generated marker. The existing single-file
            // contract then leaves that unrelated declaration outside the generated subset.
        }
    }
}

private func containsUnsupportedNode(_ node: ViewNode) -> Bool {
    if case .native = node { return true }
    return node.children.contains(where: containsUnsupportedNode)
}
