import Testing
import RefractIR

@Test func platformSelectionRetainsAllTypedBranches() {
    let alternatives = PlatformAlternatives(
        ios: Expression(.stringLiteral("iOS")),
        android: Expression(.stringLiteral("Android")),
        harmonyOS: Expression(.stringLiteral("HarmonyOS"))
    )
    #expect(alternatives.value(for: .ios).value == .stringLiteral("iOS"))
    #expect(alternatives.value(for: .android).value == .stringLiteral("Android"))
    #expect(alternatives.value(for: .harmonyOS).value == .stringLiteral("HarmonyOS"))
}

@Test func nativeArgumentTypeIsNeverInvented() {
    let argument = NativeArgument(label: "count", expression: Expression(.reference("count")), type: nil)
    #expect(argument.type == nil)
    #expect(argument.label == "count")
}
