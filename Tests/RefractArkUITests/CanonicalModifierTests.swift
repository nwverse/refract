import Testing
import RefractIR
import RefractMapping
@testable import RefractCompose
@testable import RefractArkUI

private let styledMapping = Mapping(
    android: PlatformMapping(tokens: TokenSet(
        spacing: ["DesignSpacing.medium": "AppSpacing.medium"],
        radius: ["DesignRadius.small": "AppRadius.small"],
        font: ["DesignTypography.title": "AppTypography.title"],
        color: ["DesignColors.secondary": "AppColors.secondary", "DesignColors.surface": "AppColors.surface"]
    )),
    harmonyOS: PlatformMapping(tokens: TokenSet(
        spacing: ["DesignSpacing.medium": "AppSpacing.medium"],
        radius: ["DesignRadius.small": "AppRadius.small"],
        font: ["DesignTypography.title": "AppTypography.title"],
        color: ["DesignColors.secondary": "AppColors.secondary", "DesignColors.surface": "AppColors.surface"]
    ))
)

@Test func canonicalStyledTextUsesDirectNativeTokensAndShape() throws {
    let modifiers = [
        Modifier(name: "font", arguments: [Expression(.reference("DesignTypography.title"))], argumentLabels: [nil]),
        Modifier(name: "foregroundStyle", arguments: [Expression(.reference("DesignColors.secondary"))], argumentLabels: [nil]),
        Modifier(name: "padding", arguments: [Expression(.reference("DesignSpacing.medium"))], argumentLabels: [nil]),
        Modifier(name: "frame", arguments: [Expression(.reference(".infinity"))], argumentLabels: ["maxWidth"]),
        Modifier(name: "background", arguments: [Expression(.reference("DesignColors.surface"))], argumentLabels: [nil]),
        Modifier(name: "cornerRadius", arguments: [Expression(.reference("DesignRadius.small"))], argumentLabels: [nil]),
        Modifier(name: "opacity", arguments: [Expression(.numberLiteral("0.8"))], argumentLabels: [nil]),
    ]
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Styled", body: .text(Expression(.stringLiteral("Appearance")), modifiers: modifiers, location: nil)),
    ])
    let kotlin = try ComposeBackend().generate(module: module, mapping: styledMapping)
    #expect(kotlin.contains(".padding(all = AppSpacing.medium)"))
    #expect(kotlin.contains(".fillMaxWidth()"))
    #expect(kotlin.contains(".background(AppColors.surface, RoundedCornerShape(AppRadius.small))"))
    #expect(kotlin.contains(".alpha(0.8f)"))
    #expect(kotlin.contains("color = AppColors.secondary"))
    #expect(kotlin.contains("style = AppTypography.title"))
    #expect(!kotlin.contains(".clip("))

    let ark = try ArkUIBackend().generate(module: module, mapping: styledMapping)
    #expect(ark.contains(".padding(AppSpacing.medium)"))
    #expect(ark.contains(".width('100%')"))
    #expect(ark.contains(".backgroundColor(AppColors.surface)\n.borderRadius(AppRadius.small)\n.opacity(0.8)"))
    #expect(ark.contains(".font(AppTypography.title)\n.fontColor(AppColors.secondary)"))
}

@Test func canonicalFrameAndDirectionalPaddingPreserveDimensions() throws {
    let modifiers = [
        Modifier(name: "padding", arguments: [Expression(.reference(".horizontal")), Expression(.numberLiteral("16"))],
                 argumentLabels: ["horizontal", "value"]),
        Modifier(name: "frame", arguments: [Expression(.numberLiteral("120")), Expression(.numberLiteral("44"))],
                 argumentLabels: ["width", "height"]),
    ]
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Dimensions", body: .text(Expression(.stringLiteral("Text")), modifiers: modifiers, location: nil)),
    ])
    let kotlin = try ComposeBackend().generate(module: module)
    #expect(kotlin.contains(".padding(horizontal = 16.dp).size(width = 120.dp, height = 44.dp)"))
    let ark = try ArkUIBackend().generate(module: module)
    #expect(ark.contains(".padding({ left: 16, right: 16 })\n.width(120)\n.height(44)"))
}

@Test(arguments: [
    [Modifier(name: "cornerRadius", arguments: [Expression(.numberLiteral("4"))], argumentLabels: [nil])],
    [Modifier(name: "frame", arguments: [Expression(.numberLiteral("100"))], argumentLabels: ["maxWidth"])],
    [Modifier(name: "opacity", arguments: [Expression(.numberLiteral("1.1"))], argumentLabels: [nil])],
    [Modifier(name: "font", arguments: [Expression(.reference("DesignTypography.title"))], argumentLabels: [nil])],
])
func invalidModifierShapesAreRejected(modifiers: [Modifier]) {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Invalid", body: .stack(axis: .vertical, children: [], modifiers: modifiers, location: nil)),
    ])
    #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: module, mapping: styledMapping) }
    #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: module, mapping: styledMapping) }
}
