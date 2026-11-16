import Testing
import RefractGolden

@Test func nativeMeasurementGoldenRetainsTheActualControlSemantics() throws {
    let fixture = try #require(CorpusLoader.load(repository: GoldenTests.repository).first {
        $0.name == "interop-native-measurement"
    })
    let result = try GoldenRunner.generate(fixture)
    #expect(GoldenRunner.differences(for: fixture, result: result) == [])
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("style = MaterialTheme.typography.bodyLarge"))
    #expect(kotlin.contains("padding(horizontal = 16.dp, vertical = 8.dp)"))
    #expect(kotlin.contains("remember(model, row.id)"))
    #expect(kotlin.contains("onCheckedChange = onCheckedChange"))
    #expect(kotlin.contains("Switch(\n"))
    #expect(kotlin.contains("modifier = Modifier.testTag(\"settings_toggle\").semantics { contentDescription = row.title }"))
    #expect(!kotlin.contains("Row(\n                    modifier = Modifier.testTag"))
    let ark = try #require(result.arkTS)
    #expect(ark.contains(".font(AppTypography.rowTitle)"))
    let toggleChain = "              Toggle({ type: ToggleType.Switch, isOn: row.enabled })\n" +
        "                .onChange((enabled: boolean) => {\n" +
        "                  this.model.setEnabled(row.id, enabled);\n" +
        "                })\n" +
        "                .id('settings_toggle').accessibilityText(row.title)"
    #expect(ark.contains(toggleChain))
    #expect(ark.contains("            }\n            .justifyContent(FlexAlign.SpaceBetween)"))
    #expect(!ark.contains(".justifyContent(FlexAlign.SpaceBetween)\n    .accessibilityText(row.title)"))
    #expect(!ark.contains("androidx.compose"))
    #expect(!ark.contains("remember("))
}
