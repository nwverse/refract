import RefractIR
import SwiftSyntax

/// Bounded `TabView(selection:)` and overflow `Menu` parsing.
///
/// Only a finite, statically typed tab container is accepted: zero-argument same-file generated children with
/// `.tabItem { Label(...) }`, a local no-payload `Hashable` selection enum, and a single `.toolbar` overflow menu
/// whose actions are typed model calls. Unsupported container styles, dynamic destinations and arbitrary
/// navigation graphs are build-time errors, never a silent approximation. See `docs/navigation.md`.
extension Builder {
    func tabView(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label?.text == "selection",
              let projection = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              call.additionalTrailingClosures.isEmpty else {
            error("RFNAV401", "TabView requires one `selection: $tab` binding to a local tab selection.",
                  "Use `TabView(selection: $tab) { ... }` with `@State private var tab: Tab = .home`", at: call)
            return nil
        }
        let selectionName = String(projection.baseName.text.dropFirst())
        guard let selection = currentStates.compactMap({ state -> (String, String)? in
            guard case let .tabSelection(name, enumName, _) = state else { return nil }
            return (name, enumName)
        }).first, selection.0 == selectionName else {
            error("RFNAV402", "TabView selection must be the declared local tab `@State` enum property.",
                  "Use `@State private var tab: Tab = .home` with a no-payload `Hashable` enum", at: projection)
            return nil
        }
        guard currentStates.allSatisfy({ state in
            switch state {
            case .model, .tabSelection: true
            case .state, .binding, .navigationPath, .nativeHost: false
            }
        }), currentStates.filter({ if case .tabSelection = $0 { true } else { false } }).count == 1 else {
            error("RFNAV402", "A tab root accepts only declared model inputs and one tab selection.",
                  "Keep scalar local state in a typed child screen; use one `@State private var tab: Tab`", at: projection)
            return nil
        }
        guard let declaration = enums.first(where: { $0.name == selection.1 }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty else {
            error("RFNAV402", "Tab selection needs a local `Hashable` enum without payloads.",
                  "Use `enum Tab: Hashable { case home }`; per-tab data belongs in the tab screen's own model", at: projection)
            return nil
        }
        guard let closure = call.trailingClosure, !closure.statements.isEmpty else {
            error("RFNAV401", "TabView needs at least one typed tab destination.",
                  "List one generated zero-argument child View per tab with `.tabItem { Label(...) }`", at: call)
            return nil
        }
        var destinations: [TabDestination] = []
        var menuTitle: Expression?
        var menuSymbol: String?
        var menuActions: [OverflowMenuAction] = []
        for statement in closure.statements {
            guard let destination = tabDestination(statement, enumDeclaration: declaration,
                                                   menuTitle: &menuTitle, menuSymbol: &menuSymbol,
                                                   menuActions: &menuActions) else { return nil }
            destinations.append(destination)
        }
        guard destinations.map(\.caseName) == declaration.cases else {
            error("RFNAV403", "Tab destinations must cover every selection enum case exactly once, in enum order.",
                  "Declare one `.tag(.case)` per case of `\(declaration.name)`, ordered like the enum cases", at: call)
            return nil
        }
        return .tabView(TabViewNode(selectionName: selectionName, rootName: currentViewName ?? "",
                                    enumName: declaration.name, destinations: destinations,
                                    menuTitle: menuTitle, menuSymbol: menuSymbol, menuActions: menuActions,
                                    models: currentModels), location: location(of: call))
    }

    /// Parses one `Child().tabItem { Label(...) }.tag(.case)` statement, collecting an optional trailing `.toolbar`.
    private func tabDestination(_ statement: CodeBlockItemSyntax, enumDeclaration: EnumDeclaration,
                                menuTitle: inout Expression?, menuSymbol: inout String?,
                                menuActions: inout [OverflowMenuAction]) -> TabDestination? {
        guard let expression = statement.item.as(ExprSyntax.self) else {
            error("RFNAV401", "Each TabView child must be one generated View expression with a tab item.",
                  "Use `HomeScreen().tabItem { Label(\"tab.home\", systemImage: \"house\") }.tag(.home)`", at: statement)
            return nil
        }
        var call = expression.as(FunctionCallExprSyntax.self)
        var baseExpression = expression
        // Unwrap modifier chains: the deepest call is the child View, outer members are `.tag`, `.tabItem`, `.toolbar`.
        var tagCase: String?
        var item: (title: Expression, symbol: String)?
        var sawToolbar = false
        while let member = call?.calledExpression.as(MemberAccessExprSyntax.self), let inner = member.base {
            let name = member.declName.baseName.text
            switch name {
            case "tag":
                guard tagCase == nil, call!.arguments.count == 1, call!.arguments.first?.label == nil,
                      let tag = call!.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                      tag.base == nil, tag.declName.argumentNames == nil,
                      enumDeclaration.cases.contains(tag.declName.baseName.text) else {
                    error("RFNAV403", "A tab `.tag` must be one static case of the selection enum.",
                          "Use `.tag(.home)` with a case of `\(enumDeclaration.name)`", at: call!)
                    return nil
                }
                tagCase = tag.declName.baseName.text
            case "tabItem":
                guard item == nil, call!.arguments.isEmpty,
                      let itemClosure = call!.trailingClosure, itemClosure.statements.count == 1,
                      let labelCall = itemClosure.statements.first?.item.as(FunctionCallExprSyntax.self),
                      labelCall.calledExpression.trimmedDescription == "Label" else {
                    error("RFNAV401", "A tab item needs exactly one `Label` with a localized title and system symbol.",
                          "Use `.tabItem { Label(\"tab.home\", systemImage: \"house\") }`", at: call!)
                    return nil
                }
                var parser = LocalizationFrontend(file: file, converter: converter, scalar: {
                    TypedExpression(self.viewScalar($0), nil)
                }, stateText: stateText)
                guard let title = tabLabel(labelCall, parser: &parser) else {
                    diagnostics.append(contentsOf: parser.diagnostics)
                    return nil
                }
                item = title
            case "toolbar":
                guard !sawToolbar, call!.arguments.isEmpty, let toolbar = call!.trailingClosure else {
                    error("RFNAV404", "The bounded toolbar accepts only one trailing ToolbarItem/Menu closure.",
                          "Use `.toolbar { ToolbarItem { Menu { ... } label: { Label(...) } } }`", at: call!)
                    return nil
                }
                sawToolbar = true
                guard overflowMenu(toolbar, menuTitle: &menuTitle, menuSymbol: &menuSymbol,
                                   menuActions: &menuActions) == true else { return nil }
            default:
                error("RFNAV401", "Only `.tag`, `.tabItem` and one `.toolbar` are supported on tab destinations.",
                      "Apply other styling inside the child View's own body", at: call!)
                return nil
            }
            baseExpression = inner
            call = inner.as(FunctionCallExprSyntax.self)
        }
        guard let childCall = baseExpression.as(FunctionCallExprSyntax.self),
              childCall.trailingClosure == nil, childCall.additionalTrailingClosures.isEmpty,
              childCall.arguments.isEmpty,
              let viewName = childCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let childDeclaration = viewDeclarations[viewName], viewName != currentViewName else {
            error("RFNAV403", "A tab destination must be a zero-argument same-file generated View.",
                  "Use `HomeScreen()`; give the tab its own declared model or no inputs", at: baseExpression)
            return nil
        }
        let hasInputs = childDeclaration.memberBlock.members.contains { member in
            guard let binding = member.decl.as(VariableDeclSyntax.self)?.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return false }
            return identifier != "body"
        }
        guard !hasInputs else {
            error("RFNAV403", "Tab destination `\(viewName)` must not declare stored inputs.",
                  "Pass data into a tab through its own model input only when a host supplies it; this slice accepts no inputs", at: childCall)
            return nil
        }
        guard let tagCase, let item else {
            error("RFNAV401", "Every tab destination needs both `.tabItem { Label(...) }` and `.tag(.case)`.",
                  "Add the tab label and the static selection tag", at: expression)
            return nil
        }
        return TabDestination(caseName: tagCase, viewName: viewName, title: item.title, symbol: item.symbol)
    }

    private func tabLabel(_ call: FunctionCallExprSyntax,
                          parser: inout LocalizationFrontend) -> (title: Expression, symbol: String)? {
        guard call.arguments.map(\.label?.text) == [nil, "systemImage"],
              let symbol = stringLiteral(call.arguments.last!.expression),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let title = parser.localized(call.arguments.first!.expression) else {
            error("RFNAV401", "A tab Label requires a canonical localized title and a literal system symbol.",
                  "Use `Label(\"tab.home\", systemImage: \"house\")`", at: call)
            return nil
        }
        return (title, symbol)
    }

    /// Parses `.toolbar { ToolbarItem { Menu { Button ... } label: { Label(...) } } }`. Returns false on failure.
    private func overflowMenu(_ toolbar: ClosureExprSyntax, menuTitle: inout Expression?,
                              menuSymbol: inout String?, menuActions: inout [OverflowMenuAction]) -> Bool {
        guard toolbar.statements.count == 1,
              let itemCall = toolbar.statements.first?.item.as(FunctionCallExprSyntax.self),
              itemCall.calledExpression.trimmedDescription == "ToolbarItem",
              itemCall.arguments.isEmpty || itemCall.arguments.map(\.label?.text) == ["placement"],
              let toolbarBody = itemCall.trailingClosure, toolbarBody.statements.count == 1,
              let menuCall = toolbarBody.statements.first?.item.as(FunctionCallExprSyntax.self),
              menuCall.calledExpression.trimmedDescription == "Menu" else {
            error("RFNAV404", "The bounded toolbar is one ToolbarItem containing one overflow Menu.",
                  "Use `.toolbar { ToolbarItem { Menu { ... } label: { Label(...) } } }`; drawers and other containers are unsupported", at: toolbar)
            return false
        }
        guard menuCall.arguments.isEmpty, menuCall.additionalTrailingClosures.count == 1,
              menuCall.additionalTrailingClosures.first?.label.text == "label",
              let labelClosure = menuCall.additionalTrailingClosures.first?.closure,
              labelClosure.statements.count == 1,
              let labelCall = labelClosure.statements.first?.item.as(FunctionCallExprSyntax.self),
              let actionsClosure = menuCall.trailingClosure, !actionsClosure.statements.isEmpty else {
            error("RFNAV404", "The overflow Menu needs an action closure and one Label.",
                  "Use `Menu { Button(\"menu.refresh\") { model.refresh() } } label: { Label(\"menu.more\", systemImage: \"ellipsis\") }`", at: menuCall)
            return false
        }
        var parser = LocalizationFrontend(file: file, converter: converter, scalar: {
            TypedExpression(self.viewScalar($0), nil)
        }, stateText: stateText)
        guard let label = tabLabel(labelCall, parser: &parser) else {
            diagnostics.append(contentsOf: parser.diagnostics)
            return false
        }
        menuTitle = label.title
        menuSymbol = label.symbol
        var actions: [OverflowMenuAction] = []
        for statement in actionsClosure.statements {
            guard let button = statement.item.as(FunctionCallExprSyntax.self),
                  button.calledExpression.trimmedDescription == "Button",
                  button.arguments.count == 1, button.arguments.first?.label == nil,
                  button.additionalTrailingClosures.isEmpty,
                  button.trailingClosure != nil else {
                error("RFNAV404", "An overflow menu action is one localized Button with a typed model action.",
                      "Use `Button(\"menu.refresh\") { model.refresh() }`", at: statement)
                return false
            }
            guard let title = parser.localized(button.arguments.first!.expression) else {
                diagnostics.append(contentsOf: parser.diagnostics)
                return false
            }
            guard let action = modelActionFromMenu(button.trailingClosure!) else { return false }
            actions.append(OverflowMenuAction(title: title, action: action))
        }
        menuActions = actions
        return true
    }

    private func modelActionFromMenu(_ closure: ClosureExprSyntax) -> StateAction? {
        guard closure.statements.count == 1,
              let expression = closure.statements.first?.item.as(ExprSyntax.self),
              let action = modelAction(expression) else {
            error("RFNAV404", "An overflow menu action must call one declared model method.",
                  "Use `{ model.refresh() }`; local state mutations and closures are not menu actions", at: closure)
            return nil
        }
        return action
    }
}
