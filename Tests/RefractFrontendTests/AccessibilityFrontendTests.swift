import Foundation
import Testing
import RefractIR
import RefractGolden
import RefractMapping
@testable import RefractFrontend

@Test func accessibilityTextAndActionsRetainTypedNativeSemantics() throws {
    let fixture = FixtureCase(name: "accessibility-actions-traversal", status: .ready,
        input: try String(contentsOfFile: "Fixtures/accessibility-actions-traversal/Input.swift", encoding: .utf8),
        mapping: try String(contentsOfFile: "Fixtures/accessibility-actions-traversal/refract.json", encoding: .utf8),
        expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("contentDescription = label0 + \" \" + hint0"))
    #expect(kotlin.contains("rememberUpdatedState(stringResource(R.string.accessibility_sync_label))"))
    #expect(kotlin.contains("stateDescription = value1"))
    #expect(kotlin.contains("rememberUpdatedState(stringResource(R.string.accessibility_sync_status, model.syncStatus.value))"))
    #expect(kotlin.contains("CustomAccessibilityAction(label = accessibilityAction0)"))
    #expect(kotlin.contains("isTraversalGroup = true"))
    #expect(kotlin.contains("traversalIndex = 1f"))
    let ark = try #require(result.arkTS)
    #expect(ark.contains(".accessibilityText($r('app.string.accessibility_sync_label'))"))
    #expect(ark.contains(".accessibilityDescription($r('app.string.accessibility_sync_hint'))"))
    #expect(ark.contains(".accessibilityStateDescription($r('app.string.accessibility_sync_status', this.model.syncStatus))"))
    #expect(ark.contains(".accessibilityCustomActions(["))
    #expect(ark.contains(".id('sync_now')"))
    #expect(ark.contains(".accessibilityNextFocusId('sync_details')"))
    #expect(!ark.contains("hintText"))
}

@Test func imageAccessibilityDescriptionsRetainOptionalAliasesInListRows() throws {
    let fixture = FixtureCase(name: "list-image-accessibility-descriptions", status: .ready,
        input: try String(contentsOfFile: "Fixtures/list-image-accessibility-descriptions/Input.swift", encoding: .utf8),
        mapping: try String(contentsOfFile: "Fixtures/list-image-accessibility-descriptions/refract.json", encoding: .utf8),
        expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("contentDescription = value + \" \" + value"))
    #expect(kotlin.contains("stateDescription = value"))
    let ark = try #require(result.arkTS)
    #expect(ark.contains(".accessibilityText(value)"), Comment(rawValue: ark))
    #expect(ark.contains(".accessibilityDescription(value)"), Comment(rawValue: ark))
    #expect(ark.contains(".accessibilityStateDescription(value)"), Comment(rawValue: ark))
    #expect(ark.contains(".width(44)"), Comment(rawValue: ark))
    #expect(!ark.contains("Description(this.value)"), Comment(rawValue: ark))
}

@Test func concreteViewsRetainOptionalAccessibilityAliasesInListRows() throws {
    let fixture = FixtureCase(name: "list-accessibility-local-aliases", status: .ready,
        input: try String(contentsOfFile: "Fixtures/list-accessibility-local-aliases/Input.swift", encoding: .utf8),
        mapping: try String(contentsOfFile: "Fixtures/list-accessibility-local-aliases/refract.json", encoding: .utf8),
        expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("contentDescription = value + \" \" + value"))
    #expect(kotlin.contains("stateDescription = value"))
    #expect(kotlin.contains("checked = row.enabled"))
    let ark = try #require(result.arkTS)
    #expect(ark.components(separatedBy: ".accessibilityText(value)").count == 6, Comment(rawValue: ark))
    #expect(ark.components(separatedBy: ".accessibilityDescription(value)").count == 6, Comment(rawValue: ark))
    #expect(ark.components(separatedBy: ".accessibilityStateDescription(value)").count == 6, Comment(rawValue: ark))
    #expect(ark.contains("Toggle({ type: ToggleType.Switch, isOn: row.enabled })"), Comment(rawValue: ark))
    #expect(ark.contains("this.model.setEnabled(row.id, enabled);"), Comment(rawValue: ark))
    #expect(ark.contains("Scroll()"), Comment(rawValue: ark))
    #expect(ark.contains("const value = this.description;"), Comment(rawValue: ark))
    #expect(!ark.contains("this.value"), Comment(rawValue: ark))
}

@Test(arguments: [
    ".accessibilityHint(Text(verbatim: \"Not localized\"))",
    ".accessibilityHint(\"not.text\")",
    ".accessibilityValue(Text(verbatim: \"Not localized\"))",
])
func accessibilityTextRejectsUnlocalizedOrInvalidSource(_ modifier: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            Button("accessibility.sync.now") { }
                \(modifier)
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code.hasPrefix("RFACCESS") || $0.code.hasPrefix("R.string.") })
}

@Test func customActionRejectsAnUntypedCallback() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            Button("accessibility.sync.now") { }
                .accessibilityAction(named: Text("accessibility.sync.action")) { unknownAction() }
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS002" })
}

@Test func traversalRejectsIncompleteOrCyclicDeclarations() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            VStack {
                Button("accessibility.sync.now") { }
                    .accessibilityIdentifier("sync_now")
                Button("accessibility.sync.details") { }
                    .accessibilityIdentifier("sync_details")
            }
            .accessibilityTraversal([
                .accessibility("sync_now", after: "sync_details"),
                .accessibility("sync_details", after: "sync_now"),
            ])
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS003" })
}

@Test func traversalRejectsSelfPredecessorAndPreservesEarlierPredecessor() throws {
    for platform in ["android", "harmonyOS"] {
        let branch = """
                        VStack {
                            Button("accessibility.sync.now") { }
                                .accessibilityIdentifier("sync_now")
                            Button("accessibility.sync.details") { }
                                .accessibilityIdentifier("sync_details")
                        }
                        .accessibilityTraversal([
                            .accessibility("sync_now"),
                            .accessibility("sync_details", after: "sync_now"),
                        ])
        """
        let control = "Text(verbatim: \"Control\")"
        let arguments = platform == "android"
            ? "ios: { \(control) }, android: { \(branch) }, harmonyOS: { \(control) }"
            : "ios: { \(control) }, android: { \(control) }, harmonyOS: { \(branch) }"
        let source = SourceFile(path: "Input.swift", contents: """
        struct Ordered: View {
            var body: some View {
                refractView(\(arguments))
            }
        }
        """)
        let unit = Frontend.parse(source)
        #expect(unit.diagnostics.isEmpty)
        let screen = try #require(unit.module.screens.first)
        guard case let .platformView(alternatives, _) = screen.body else {
            Issue.record("Expected explicit platform traversal branches")
            return
        }
        for children in [alternatives.android, alternatives.harmonyOS] {
            guard case let .stack(_, _, modifiers, _)? = children.first else { continue }
            let traversal = try #require(modifiers.first(where: { $0.name == "accessibilityTraversal" }))
            guard case let .accessibilityTraversal(order) = traversal.arguments.first?.value else {
                Issue.record("Expected typed accessibility traversal IR")
                continue
            }
            #expect(order.steps == [
                AccessibilityTraversal.Step(name: "sync_now"),
                AccessibilityTraversal.Step(name: "sync_details", after: "sync_now"),
            ])
        }

        let malformedSequences = [
            source.contents.replacingOccurrences(
                of: ".accessibility(\"sync_now\"),",
                with: ".accessibility(\"sync_now\", after: \"sync_now\"),"),
            source.contents.replacingOccurrences(
                of: ".accessibility(\"sync_details\", after: \"sync_now\"),",
                with: ".accessibility(\"sync_now\"),"),
            source.contents.replacingOccurrences(
                of: ".accessibility(\"sync_now\"),",
                with: ".accessibility(\"sync_now\", after: \"sync_details\"),"),
        ]
        for malformed in malformedSequences {
            let rejected = Frontend.parse(SourceFile(path: "Input.swift", contents: malformed))
            #expect(rejected.hasErrors)
            #expect(rejected.module.screens.isEmpty)
            #expect(rejected.diagnostics.filter { $0.code == "RFACCESS003" }.count == 1)
        }
    }
}

@Test func accessibilityRejectsDuplicateAndWrongPlatformModifiers() {
    let source = SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            Button("accessibility.sync.now") { }
                .accessibilityLabel(Text("accessibility.sync.label"))
                .accessibilityLabel(Text("accessibility.sync.label"))
        }
    }
    """)
    let unit = Frontend.parse(source)
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS004" })
}

@Test func accessibilitySortPriorityMustStayInTheIOSBranch() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            Button("accessibility.sync.details") { }
                .accessibilitySortPriority(-1)
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS003" })
}

@Test func accessibilityActionsCannotRepeatOnOneReceiver() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { func syncNow() }
    struct Invalid: View {
        let model: Model
        var body: some View {
            Button("accessibility.sync.now") { model.syncNow() }
                .accessibilityAction(named: Text("accessibility.sync.action")) { model.syncNow() }
                .accessibilityAction(named: Text("accessibility.sync.action")) { model.syncNow() }
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS002" })
}

@Test func minimumAPIMappingRejectsInvalidLevels() throws {
    let mapping = try String(contentsOfFile: "Fixtures/accessibility-actions-traversal/refract.json", encoding: .utf8)
        .replacingOccurrences(of: "\"minimumAPI\": 26", with: "\"minimumAPI\": 11")
    let result = Mapping.validate(data: Data(mapping.utf8), file: "refract.json")
    guard case let .failure(error) = result else {
        Issue.record("Expected an invalid minimum API diagnostic")
        return
    }
    #expect(error.diagnostics.contains { $0.code == "mappingMinimumAPI" })
}
@Test func missingAccessibilityAPIIsAnExplicitGenerationError() throws {
    let base = try String(contentsOfFile: "Fixtures/accessibility-actions-traversal/refract.json", encoding: .utf8)
    for (level, required) in [(12, 18), (18, 23), (23, 26)] {
        let mapping = base.replacingOccurrences(of: "\"minimumAPI\": 26", with: "\"minimumAPI\": \(level)")
        let fixture = FixtureCase(name: "accessibility-actions-traversal", status: .ready,
            input: try String(contentsOfFile: "Fixtures/accessibility-actions-traversal/Input.swift", encoding: .utf8),
            mapping: mapping, expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
        let result = try GoldenRunner.generate(fixture)
        #expect(result.kotlin == nil)
        #expect(result.arkTS == nil)
        #expect(result.diagnostics.contains { $0.code == "RFACCESS005" && $0.message.contains("API \(required)") })
    }
}
