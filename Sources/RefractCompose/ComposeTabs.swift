import RefractIR
import RefractMapping

/// Bounded typed tabs + overflow menu lowering.
///
/// Generated Android code keeps selection and menu semantics native: Material 3 `NavigationBarItem` carries the
/// selected state and role, `DropdownMenu` carries menu-item semantics. There is no router, no drawer substitution
/// and no second selection owner: the host passes `selectedTab` and receives `onTabChange`, exactly like a
/// hand-written controlled component. Back behavior and per-tab saved state stay in the native host.
///
/// Tab icons use the same typed `symbols` mapping as `Image(systemName:)`; an unmapped SF symbol is a build-time
/// diagnostic, never a guessed drawable.
extension ComposeBackend {
    func emitTabView(_ tabs: TabViewNode, isRoot: Bool, location: SourceLocation?,
                     into out: inout KotlinWriter, context: inout Context) throws {
        guard isRoot, !tabs.rootName.isEmpty, !tabs.destinations.isEmpty,
              let declaration = context.module.enums.first(where: { $0.name == tabs.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              tabs.destinations.map(\.caseName) == declaration.cases else {
            throw Diagnostic(code: "RFNAV403", message: "A native tab view needs exhaustive ordered finite destinations.",
                             suggestion: "Validate the same-file Hashable selection enum in the frontend", location: location)
        }
        context.imports.insert("androidx.compose.foundation.layout.Column")
        context.imports.insert("androidx.compose.foundation.layout.Box")
        context.imports.insert("androidx.compose.foundation.layout.fillMaxSize")
        out.open("Column(modifier = modifier.fillMaxSize())")
        // `weight` is a ColumnScope extension; it must not be imported as a top-level Modifier extension.
        out.open("Box(modifier = Modifier.weight(1f))")
        out.line("\(tabs.rootName)Destinations(tab = \(tabs.selectionName))")
        out.close()
        try emitTabBar(tabs, into: &out, context: &context)
        out.close()
    }

    private func emitTabBar(_ tabs: TabViewNode, into out: inout KotlinWriter, context: inout Context) throws {
        context.imports.insert("androidx.compose.material3.NavigationBar")
        context.imports.insert("androidx.compose.material3.NavigationBarItem")
        out.open("NavigationBar")
        for destination in tabs.destinations {
            out.open("NavigationBarItem(")
            out.line("selected = \(tabs.selectionName) == \(tabs.enumName).\(destination.caseName),")
            out.line("onClick = { on\(tabs.selectionName.uppercasingFirst())Change(\(tabs.enumName).\(destination.caseName)) },")
            out.line("icon = {")
            out.depth += 1
            try emitTabSymbol(destination.symbol, into: &out, context: &context)
            out.depth -= 1
            out.line("},")
            // The last named lambda argument must not carry a trailing comma before `)`.
            out.line("label = {")
            out.depth += 1
            try emit(.text(destination.title, modifiers: [], location: nil), into: &out, context: &context)
            out.depth -= 1
            out.line("}")
            out.closeParen()
        }
        if !tabs.menuActions.isEmpty {
            try emitOverflowMenu(tabs, into: &out, context: &context)
        }
        out.close()
    }

    private func emitOverflowMenu(_ tabs: TabViewNode, into out: inout KotlinWriter, context: inout Context) throws {
        context.imports.insert("androidx.compose.material3.DropdownMenu")
        context.imports.insert("androidx.compose.material3.DropdownMenuItem")
        context.imports.insert("androidx.compose.material3.IconButton")
        context.imports.insert("androidx.compose.runtime.mutableStateOf")
        context.imports.insert("androidx.compose.runtime.remember")
        context.imports.insert("androidx.compose.runtime.getValue")
        context.imports.insert("androidx.compose.runtime.setValue")
        out.open("Box")
        out.line("var menuExpanded by remember { mutableStateOf(false) }")
        // The icon-only overflow affordance keeps its localized accessibility label on the clickable button,
        // so screen readers announce the action instead of a silent icon. The label is read in composable scope
        // and then referenced from the non-composable semantics lambda.
        if let menuTitle = tabs.menuTitle {
            context.imports.insert("androidx.compose.ui.semantics.contentDescription")
            context.imports.insert("androidx.compose.ui.semantics.semantics")
            context.imports.insert("androidx.compose.ui.res.stringResource")
            out.line("val menuContentDescription = \(try renderExpression(menuTitle, context: &context))")
            out.open("IconButton(onClick = { menuExpanded = true }, modifier = Modifier.semantics { contentDescription = menuContentDescription })")
        } else {
            out.open("IconButton(onClick = { menuExpanded = true })")
        }
        if let symbol = tabs.menuSymbol {
            try emitTabSymbol(symbol, into: &out, context: &context)
        }
        out.close()
        out.open("DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false })")
        for action in tabs.menuActions {
            out.open("DropdownMenuItem(")
            out.line("text = {")
            out.depth += 1
            try emit(.text(action.title, modifiers: [], location: nil), into: &out, context: &context)
            out.depth -= 1
            out.line("},")
            out.line("onClick = { menuExpanded = false; \(try renderAction(action.action, context: &context)) }")
            out.closeParen()
        }
        out.close()
        out.close()    }

    private func emitTabSymbol(_ symbol: String, into out: inout KotlinWriter, context: inout Context) throws {
        let mapped = try context.mapping.symbol(symbol, platform: .android, location: nil)
        context.imports.insert("androidx.compose.material3.Icon")
        switch mapped.kind {
        case .materialIcon:
            context.imports.insert("androidx.compose.material.icons.Icons")
            context.imports.insert("androidx.compose.material.icons.filled.\(mapped.name)")
            out.line("Icon(imageVector = Icons.Default.\(mapped.name), contentDescription = null)")
        case .drawable:
            guard let resourceClass = context.androidResourceClass else {
                throw Diagnostic(code: "RF-C002", message: "A mapped tab drawable needs the Android R class.",
                                 suggestion: "Set android.resources.className to the application's fully qualified R class.")
            }
            context.imports.insert("androidx.compose.ui.res.painterResource")
            context.imports.insert(resourceClass)
            out.line("Icon(painter = painterResource(R.drawable.\(mapped.name)), contentDescription = null)")
        case .media:
            throw Diagnostic(code: "RF-C002", message: "A media mapping is only valid for ArkUI.",
                             suggestion: "Use materialIcon or drawable for Android tab icons.")
        }
    }

    func emitTabDestinations(_ tabs: TabViewNode, into out: inout KotlinWriter, context: inout Context) throws {
        out.line()
        out.line("@Composable")
        out.line("public fun \(tabs.rootName)Destinations(")
        out.depth += 1
        out.line("tab: \(tabs.enumName),")
        out.line("modifier: Modifier = Modifier,")
        out.depth -= 1
        out.line(") {")
        out.depth += 1
        out.open("when (tab)")
        for destination in tabs.destinations {
            guard let screen = context.module.screens.first(where: { $0.name == destination.viewName }),
                  screen.parameters.isEmpty, screen.states.isEmpty else {
                throw Diagnostic(code: "RFNAV403", message: "A tab destination must be a zero-argument generated View.",
                                 suggestion: "Keep the tab screen free of stored inputs in this slice")
            }
            out.line("\(tabs.enumName).\(destination.caseName) -> \(destination.viewName)(modifier = modifier)")
        }
        out.close()
        out.depth -= 1
        out.line("}")
    }
}
