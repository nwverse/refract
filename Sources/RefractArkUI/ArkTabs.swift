import RefractIR
import RefractMapping

/// Bounded typed tabs + overflow menu lowering for ArkUI.
///
/// The host owns the selected tab through `@Param @Require selectedTab` and receives `@Event onTabChange`; the
/// generated component renders native `Tabs`/`TabContent` with a typed `tabBar` builder carrying the selected
/// state, and a `bindMenu` overflow affordance whose items call typed model actions only. There is no
/// `NavPathStack`, no router, no second selection owner and no drawer fallback. Back behavior and page lifecycle
/// stay in the native host, exactly as for hand-written ArkUI components. This source is verified by golden tests
/// and source review only; ArkTS compilation needs the HarmonyOS toolchain (see `docs/navigation.md`).
extension Generation {
    func emitTabView(_ tabs: TabViewNode, into writer: inout ArkWriter, mapping: Mapping) throws {
        guard !tabs.rootName.isEmpty, !tabs.destinations.isEmpty,
              let declaration = module.enums.first(where: { $0.name == tabs.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              tabs.destinations.map(\.caseName) == declaration.cases else {
            throw Diagnostic(code: "RFNAV403", message: "A native tab view needs exhaustive ordered finite destinations.")
        }
        for destination in tabs.destinations {
            guard let screen = module.screens.first(where: { $0.name == destination.viewName }),
                  screen.parameters.isEmpty, screen.states.isEmpty else {
                throw Diagnostic(code: "RFNAV403", message: "A tab destination must be a zero-argument generated View.")
            }
        }
        // Selected index is derived from the host-owned selection; no parallel @Local index is kept.
        writer.open("Column()")
        writer.open("Tabs({ barPosition: BarPosition.End, index: this.\(tabIndex(tabs)) })")
        for destination in tabs.destinations {
            writer.open("TabContent()")
            writer.line("\(destination.viewName)()")
            writer.close()
            writer.depth += 1
            writer.line(".tabBar(this.\(tabs.rootName.prefix(1).lowercased())\(tabs.rootName.dropFirst())TabBar(\(try ArkExpression.emit(destination.title, mapping: mapping)), \(try tabSymbol(destination.symbol, mapping: mapping)), this.\(tabs.selectionName) === \(tabs.enumName).\(destination.caseName)))")
            writer.depth -= 1
        }
        writer.close()
        writer.depth += 1
        writer.line(".barHeight(56)")
        writer.open(".onChange((index: number) =>")
        writer.open("switch (index)")
        for (index, destination) in tabs.destinations.enumerated() {
            writer.line("case \(index): this.on\(tabs.selectionName.prefix(1).uppercased())\(tabs.selectionName.dropFirst())Change(\(tabs.enumName).\(destination.caseName)); break;")
        }
        writer.close()
        writer.close(suffix: ")")
        writer.depth -= 1
        if !tabs.menuActions.isEmpty {
            try emitTabMenu(tabs, into: &writer, mapping: mapping)
        }
        writer.close()
        writer.line(".layoutWeight(1)")
    }

    private func tabIndex(_ tabs: TabViewNode) -> String {
        // A typed derived getter is emitted once per component; it maps the host's enum selection to the native
        // tab index without duplicating selection state.
        "\(tabs.rootName.prefix(1).lowercased())\(tabs.rootName.dropFirst())TabIndex"
    }

    func emitTabHelpers(_ tabs: TabViewNode, into writer: inout ArkWriter) throws {
        writer.line("private get \(tabIndex(tabs))(): number {")
        writer.depth += 1
        writer.open("switch (this.\(tabs.selectionName))")
        for (index, destination) in tabs.destinations.enumerated() {
            writer.line("case \(tabs.enumName).\(destination.caseName): return \(index);")
        }
        writer.line("default: return 0;")
        writer.close()
        writer.depth -= 1
        writer.line("}")
        writer.line()
        writer.line("@Builder")
        writer.open("\(tabs.rootName.prefix(1).lowercased())\(tabs.rootName.dropFirst())TabBar(title: string, icon: Resource, selected: boolean)")
        writer.open("Column()")
        writer.line("Image(icon)")
        writer.depth += 1
        writer.line(".width(24)")
        writer.line(".height(24)")
        writer.line(".opacity(selected ? 1.0 : 0.6)")
        writer.depth -= 1
        writer.line("Text(title)")
        writer.depth += 1
        writer.line(".fontSize(12)")
        writer.line(".opacity(selected ? 1.0 : 0.6)")
        writer.depth -= 1
        writer.close()
        writer.close()
    }

    private func emitTabMenu(_ tabs: TabViewNode, into writer: inout ArkWriter, mapping: Mapping) throws {
        // A bounded native overflow menu bound to a trailing affordance. Only typed model actions cross the
        // boundary, so no closure registry or runtime dispatch is generated.
        guard let menuTitle = tabs.menuTitle else { return }
        writer.line("Text(\(try ArkExpression.emit(menuTitle, mapping: mapping)))")
        writer.depth += 1
        writer.line(".bindMenu([")
        writer.depth += 1
        for action in tabs.menuActions {
            writer.line("{")
            writer.depth += 1
            writer.line("value: \(try ArkExpression.emit(action.title, mapping: mapping)),")
            writer.open("action: () =>")
            writer.line(try emitLocalAction(action.action))
            writer.close(suffix: ",")
            writer.depth -= 1
            writer.line("},")
        }
        writer.depth -= 1
        writer.line("])")
        writer.depth -= 1
    }

    private func tabSymbol(_ symbol: String, mapping: Mapping) throws -> String {
        let mapped = try mapping.symbol(symbol, platform: .harmonyOS, location: nil)
        guard mapped.kind == .media else {
            throw Diagnostic(code: "RFMAP002", message: "An ArkUI tab symbol must map to an app media resource.",
                             suggestion: "Use kind `media` with a declared application media name.")
        }
        return "$r('app.media.\(mapped.name)')"
    }
}
