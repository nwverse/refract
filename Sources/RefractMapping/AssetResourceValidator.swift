import RefractIR

/// Resolves every binary resource before either backend emits. Existing mappings without an asset
/// catalog retain their legacy diagnostics; an explicitly configured catalog fails closed.
public enum AssetResourceValidator {
    public static func validate(module: Module, mapping: Mapping) throws {
        guard mapping.android.resources.assetCatalog != nil || mapping.harmonyOS.resources.assetCatalog != nil else { return }
        guard mapping.android.resources.assetCatalog != nil, mapping.harmonyOS.resources.assetCatalog != nil else {
            throw Diagnostic(code: "R.asset.not_configured", message: "Asset catalogs must be configured on both platforms.",
                             suggestion: "Declare `assetCatalog: res` on Android and `assetCatalog: resources` on HarmonyOS")
        }
        for screen in module.screens { try visit(screen.body, mapping: mapping) }
    }

    private static func visit(_ node: ViewNode, mapping: Mapping) throws {
        switch node {
        case let .image(source, _, _):
            if source.kind == .application {
                try AssetCatalog.resolveBoth(source.name, kind: .image, mapping: mapping, location: source.location)
            }
        case let .native(component, _):
            for argument in component.arguments {
                switch (argument.type, argument.expression.value) {
                case let (.rawAsset?, .rawAssetResource(name)):
                    _ = try AssetCatalog.resolveBoth(name, kind: .raw, mapping: mapping, location: argument.location)
                default: break
                }
            }
        default: break
        }
        for modifier in modifiers(of: node) where modifier.name == "font" {
            guard let argument = modifier.arguments.first else { continue }
            if case let .fontAsset(name, _) = argument.value {
                try AssetCatalog.resolveBoth(name, kind: .font, mapping: mapping, location: argument.location)
            }
        }
        for child in node.children { try visit(child, mapping: mapping) }
    }

    private static func modifiers(of node: ViewNode) -> [Modifier] {
        switch node {
        case let .text(_, modifiers, _), let .image(_, modifiers, _), let .label(_, _, modifiers, _),
             let .divider(modifiers, _), let .scroll(_, _, modifiers, _), let .list(_, modifiers, _):
            return modifiers
        case let .stack(_, _, modifiers, _), let .layout(_, _, modifiers, _), let .button(_, _, modifiers, _),
             let .toggle(_, _, modifiers, _, _, _), let .textInput(_, _, modifiers, _):
            return modifiers
        default: return []
        }
    }
}
