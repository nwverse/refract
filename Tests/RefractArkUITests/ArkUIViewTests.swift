import Testing
@testable import RefractArkUI
import RefractIR

@Test func arkUIEmitsLayoutScrollAndLeafViews() throws {
    let text: (String) -> ViewNode = { .text(Expression(.stringLiteral($0)), modifiers: [], location: nil) }
    let body = ViewNode.scroll(axis: .vertical,
        child: .layout(LayoutContainer(axis: .vertical, alignment: .leading, spacing: Expression(.layoutSpacing(.medium))), children: [
            .layout(LayoutContainer(axis: .horizontal, alignment: .center, spacing: Expression(.layoutSpacing(.small))), children: [text("Enabled"), .spacer(location: nil)], modifiers: [], location: nil),
            .layout(LayoutContainer(axis: .depth, alignment: .topLeading), children: [text("Background"), text("Foreground")], modifiers: [], location: nil),
            .image(source: ImageSource(kind: .system, name: "gear"), modifiers: [], location: nil),
            .label(title: Expression(.stringLiteral("Profile")), image: ImageSource(kind: .system, name: "person"), modifiers: [], location: nil),
            .divider(modifiers: [], location: nil),
        ], modifiers: [], location: nil), modifiers: [], location: nil)
    let output = try ArkUIBackend().generate(module: Module(sourceFile: "Input.swift", screens: [Screen(name: "Layout", body: body)]))
    #expect(output.contains("Scroll() {"))
    #expect(output.contains("Column({ space: 8 }) {"))
    #expect(output.contains(".alignItems(HorizontalAlign.Start)"))
    #expect(output.contains("Row({ space: 4 }) {"))
    #expect(output.contains("Blank()"))
    #expect(output.contains("Stack({ alignContent: Alignment.TopStart }) {"))
    #expect(output.contains("Image($r('sys.media.gear'))"))
    #expect(output.contains("Image($r('sys.media.person'))"))
    #expect(output.contains(".scrollable(ScrollDirection.Vertical)"))
    #expect(output.contains("Divider()"))
}

@Test func arkUIEmitsStableKeyLazyLists() throws {
    let items = ListItems(collection: Expression(.reference("model.items")), itemName: "item", itemType: "SettingItem",
                          keyType: .string, content: .text(Expression(.reference("item.title")), modifiers: [], location: nil))
    let body = ViewNode.list(children: [
        .section(header: Expression(.stringLiteral("General")), children: [
            .text(Expression(.stringLiteral("Profile")), modifiers: [], location: nil),
        ], location: nil),
        .forEach(items, location: nil),
    ], modifiers: [], location: nil)
    let output = try ArkUIBackend().generate(module: Module(sourceFile: "Input.swift", screens: [Screen(name: "SettingsList", body: body)]))
    #expect(output.contains("ListItemGroup({ header: Text('General') }) {"))
    #expect(output.contains("ListItem() {"))
    #expect(output.contains("LazyForEach(this.model.items, (item: SettingItem) => {"))
    #expect(output.contains("Text(item.title)"))
    #expect(output.contains("}, (item: SettingItem): string => item.id)"))
    #expect(!output.contains("this.item"))
    #expect(!output.contains("index"))
}

@Test func arkUIEmitsIntegerIdentityAsAStringKey() throws {
    let items = ListItems(collection: Expression(.reference("model.items")), itemName: "item", itemType: "SettingItem",
                          keyType: .int, content: .text(Expression(.reference("item.title")), modifiers: [], location: nil))
    let output = try ArkUIBackend().generate(module: Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Numbers", body: .list(children: [.forEach(items, location: nil)], modifiers: [], location: nil)),
    ]))
    #expect(output.contains("(item: SettingItem): string => String(item.id)"))
}

@Test func arkUIItemToggleKeepsMeasurementModifiersOnTheSwitch() throws {
    let binding = ItemBinding(model: "model", item: "row", property: "enabled", key: "id", action: "setEnabled")
    let items = ListItems(collection: Expression(.reference("model.rows")), itemName: "row", itemType: "SettingRow",
                          keyType: .int,
                          content: .toggle(title: Expression(.stringLiteral("Enabled")),
                                           value: Expression(.valueProperty(.itemBinding(binding))),
                                           modifiers: [
                                               Modifier(name: "accessibilityLabel", arguments: [Expression(.reference("row.title"))],
                                                        argumentLabels: [nil]),
                                               Modifier(name: "opacity", arguments: [Expression(.numberLiteral("0.8"))],
                                                        argumentLabels: [nil]),
                                           ],
                                           nativeModifiers: [
                                               NativeModifier(operation: .testTag(Expression(.stringLiteral("settings_toggle")))),
                                           ], location: nil))
    let body = ViewNode.list(children: [.forEach(items, location: nil)], modifiers: [], location: nil)
    let output = try ArkUIBackend().generate(module: Module(sourceFile: "Input.swift", screens: [
        Screen(name: "SettingsList", body: body),
    ]))
    let toggleChain = "            Toggle({ type: ToggleType.Switch, isOn: row.enabled })\n" +
        "              .onChange((enabled: boolean) => {\n" +
        "                this.model.setEnabled(row.id, enabled);\n" +
        "              })\n" +
        "              .id('settings_toggle').accessibilityText(row.title)"
    #expect(output.contains(toggleChain))
    let rowChain = "          }\n" +
        "          .justifyContent(FlexAlign.SpaceBetween)\n" +
        "          .opacity(0.8)"
    #expect(output.contains(rowChain))
}

@Test func arkUIRejectsInvalidImageResourceAndUnboundControl() throws {
    let image = Module(sourceFile: "Input.swift", screens: [Screen(name: "Image", body: .image(source: ImageSource(kind: .system, name: "invalid-name"), modifiers: [], location: nil))])
    #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: image) }
    let toggle = Module(sourceFile: "Input.swift", screens: [Screen(name: "Toggle", body: .toggle(title: Expression(.stringLiteral("Enabled")), value: Expression(.reference("enabled")), modifiers: [], location: nil))])
    #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: toggle) }
    let misplaced = Module(sourceFile: "Input.swift", screens: [Screen(name: "Misplaced", body: .layout(LayoutContainer(axis: .vertical), children: [.forEach(ListItems(collection: Expression(.reference("model.items")), itemName: "item", itemType: "SettingItem", keyType: .string, content: .text(Expression(.reference("item.title")), modifiers: [], location: nil)), location: nil)], modifiers: [], location: nil))])
    #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: misplaced) }
}
