import Foundation
import RefractFrontend
import RefractGolden
import RefractIR
import RefractMapping
import Testing

@Suite("Theme interaction token frontend")
struct ThemeInteractionFrontendTests {
    @Test(arguments: [
        "refractInteractionColor(DesignColors.action, enabled: isEnabled, pressed: isPressed)",
        "refractInteractionColor(DesignColors.action, enabled: isEnabled, pressed: isPressed, focused: title)",
        "refractInteractionColor(DesignSpacing.medium, enabled: isEnabled, pressed: isPressed, focused: isFocused)",
        "DesignColors.action",
    ])
    func invalidColorInputIsDiagnosed(expression: String) throws {
        let source = """
        import SwiftUI
        struct RejectTheme: View {
            @Binding var isEnabled: Bool
            @Binding var isPressed: Bool
            @Binding var isFocused: Bool
            @Binding var title: String
            var body: some View {
                Text(verbatim: "Notifications")
                    .background(\(expression))
            }
        }
        """
        let mappingURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/theme-interaction-states/refract.json")
        let mapping = try Mapping.load(contentsOf: mappingURL)
        let fixture = FixtureCase(name: "invalid-theme", status: .ready, input: source,
            mapping: String(decoding: try Data(contentsOf: mappingURL), as: UTF8.self),
            expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
        let result = try GoldenRunner.generate(fixture)
        #expect(result.diagnostics.contains {
            ["interactionToken", "missingTokenMapping", "RFVIEW003"].contains($0.code)
        }, "Unexpected diagnostics: \(result.diagnostics.map(\.rendered))")
        #expect(result.kotlin == nil)
        #expect(result.arkTS == nil)
    }
}
