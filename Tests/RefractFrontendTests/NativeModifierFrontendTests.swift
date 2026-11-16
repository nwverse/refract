import Foundation
import Testing
import RefractIR
import RefractMapping
import RefractFrontend
@testable import RefractCompose
import RefractArkUI

private let measurementMapping = Mapping(
    android: PlatformMapping(
        imports: [NativeImport(module: "example.design.AppTypography", symbols: ["AppTypography"])],
        tokens: TokenSet(font: ["DesignTypography.rowTitle": "AppTypography.rowTitle"])
    ),
    harmonyOS: PlatformMapping(
        imports: [NativeImport(module: "example.design", symbols: ["AppTypography"])],
        tokens: TokenSet(font: ["DesignTypography.rowTitle": "AppTypography.rowTitle"])
    )
)

@Test func nativeModifierPreservesAllTypedPlatformBranches() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Measurement: View {
        var body: some View {
            refractView(
                ios: { Text(verbatim: "Title").accessibilityLabel("Accessible title") },
                android: { Text(verbatim: "Title").refractNativeModifier(.testTag("row_title"), .contentDescription("Accessible title")) },
                harmonyOS: { Text(verbatim: "Title").accessibilityLabel("Accessible title").refractNativeModifier(.testTag("row_title")) }
            )
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .platformView(alternatives, _) = unit.module.screens[0].body,
          case let .text(_, iosModifiers, _) = alternatives.ios[0],
          case let .nativeModifier(_, operations, _) = alternatives.android[0] else {
        Issue.record("Expected explicit native/iOS alternatives")
        return
    }
    #expect(iosModifiers.map(\.name) == ["accessibilityLabel"])
    #expect(operations.count == 2)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains(".testTag(\"row_title\").semantics { contentDescription = \"Accessible title\" }"))
    #expect(!kotlin.contains("accessibilityText"))
    let ark = try ArkUIBackend().generate(module: unit.module)
    #expect(ark.contains(".accessibilityText('Accessible title')"))
    #expect(ark.contains(".id('row_title')"))
    #expect(!ark.contains("contentDescription"))
}

@Test func nativeModifierRejectsUnknownAndIllTypedOperations() {
    let unknown = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.eraseToAnyModifier()) } }
    """))
    #expect(unknown.diagnostics.map(\.code) == ["RFNATIVE004"])
    #expect(unknown.diagnostics[0].location != nil)
    let untyped = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.testTag(42)) } }
    """))
    #expect(untyped.diagnostics.map(\.code) == ["RFNATIVE004"])
    let receiver = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { List { Text(verbatim: "Title") }.refractNativeModifier(.retainCallback(identity: "row")) } }
    """))
    #expect(receiver.diagnostics.map(\.code) == ["RFNATIVE004"])
}

@Test func nativeModifierRejectsForgedIOSSemanticsOnOtherTargets() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Invalid", body: .text(Expression(.verbatimText("Title")), modifiers: [
            Modifier(name: "accessibilityLabel", arguments: [Expression(.stringLiteral("Title"))], argumentLabels: [nil]),
        ], location: nil)),
    ])
    #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: module) }
}

@Test func retainedModelActionUsesAllCapturedIdentityKeys() throws {
    let action = StateAction.modelMethod(model: "model", name: "refresh", arguments: [
        ActionArgument(label: nil, value: Expression(.reference("row.id"))),
    ])
    let node = ViewNode.button(
        label: .text(Expression(.verbatimText("Refresh")), modifiers: [], location: nil),
        action: action, modifiers: [], location: nil)
    let module = Module(sourceFile: "Input.swift", screens: [Screen(name: "Retained", body: node)],
                        itemTypes: [ItemType(name: "SettingRow", identity: ItemProperty(name: "id", type: .int), properties: [])])
    var context = ComposeBackend.Context(module: module, mapping: .empty)
    context.retainedItem = ("row", "SettingRow")
    var writer = KotlinWriter()
    try ComposeNativeModifier().emit(node, operations: [
        NativeModifier(operation: .retainCallback(identity: "settings.refresh")),
    ], isRoot: false, into: &writer, context: &context)
    #expect(writer.text.contains("remember(model, row.id, \"settings.refresh\")"))
    #expect(writer.text.contains("Button(onClick = onClick"))
}

@Test func directionalPaddingAndTypographyKeepNativeRowShape() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct RowShape: View {
        var body: some View {
            Text(verbatim: "Title").font(DesignTypography.rowTitle).padding(horizontal: 16, vertical: 8)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: measurementMapping)
    #expect(kotlin.contains(".padding(horizontal = 16.dp, vertical = 8.dp)"))
    #expect(kotlin.contains("style = AppTypography.rowTitle"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: measurementMapping)
    #expect(ark.contains(".padding({ left: 16, right: 16, top: 8, bottom: 8 })"))
    #expect(ark.contains(".font(AppTypography.rowTitle)"))
}
