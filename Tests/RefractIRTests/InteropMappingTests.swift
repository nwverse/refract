import Testing
import RefractIR

private let declaration = NativeDeclaration(name: "RoutePreview", parameters: [
    NativeParameter(label: "zoom", type: .double),
    NativeParameter(label: "showsTraffic", type: .bool),
])

private func target(style: NativeTarget.ArgumentStyle = .named,
                    kind: NativeTarget.Kind = .composable,
                    parameters: [NativeTarget.Parameter]? = nil,
                    arguments: [NativeTarget.Argument]? = nil) -> NativeTarget {
    NativeTarget(symbol: "RoutePreview", module: "example.maps", kind: kind, argumentStyle: style,
                 parameters: parameters ?? [
                     NativeTarget.Parameter(label: "zoom", type: .double),
                     NativeTarget.Parameter(label: "showsTraffic", type: .bool),
                 ], arguments: arguments ?? [
                     NativeTarget.Argument(source: "zoom", target: "cameraZoom"),
                     NativeTarget.Argument(source: "showsTraffic", target: "showsTraffic"),
                 ])
}

@Test func nativeMappingAcceptsExactTypedSignatures() throws {
    let result = try InteropMapping.validate(declaration: declaration, android: target(),
        harmonyOS: target(style: .object, kind: .component))
    #expect(result.android.symbol == "RoutePreview")
    #expect(result.harmonyOS.argumentStyle == .object)
}

@Test func nativeMappingReportsBothMissingPlatforms() throws {
    let error = #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration, android: nil, harmonyOS: nil)
    }
    #expect(error?.diagnostics.map(\.code) == ["RFMAP002", "RFMAP002"])
    #expect(error?.diagnostics.map(\.message).joined().contains("Android") == true)
    #expect(error?.diagnostics.map(\.message).joined().contains("HarmonyOS") == true)
}

@Test(arguments: [
    NativeTarget.ArgumentStyle.named,
    NativeTarget.ArgumentStyle.positional,
])
func nativeMappingRejectsWrongHarmonyStyle(style: NativeTarget.ArgumentStyle) throws {
    let harmony = target(style: style, kind: .component)
    let error = #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration, android: target(), harmonyOS: harmony)
    }
    #expect(error?.diagnostics.map(\.code) == ["RFMAP003"])
}

@Test func nativeMappingRejectsTypeLabelOrderAndBindingMismatches() throws {
    let parameters = [NativeTarget.Parameter(label: "showsTraffic", type: .int),
                      NativeTarget.Parameter(label: "zoom", type: .double)]
    let arguments = [NativeTarget.Argument(source: "zoom", target: "cameraZoom")]
    let error = #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration,
            android: target(parameters: parameters, arguments: arguments),
            harmonyOS: target(style: .object, kind: .component))
    }
    #expect(error?.diagnostics.count == 3)
    #expect(error?.diagnostics.allSatisfy { $0.code == "RFMAP003" } == true)
}

@Test func nativeMappingRejectsInvalidSymbolAndTargetLabel() throws {
    let invalid = NativeTarget(symbol: "RoutePreview()", module: "example.maps", kind: .composable,
        argumentStyle: .named,
        parameters: [NativeTarget.Parameter(label: "zoom", type: .double),
                     NativeTarget.Parameter(label: "showsTraffic", type: .bool)],
        arguments: [NativeTarget.Argument(source: "zoom", target: "camera zoom"),
                    NativeTarget.Argument(source: "showsTraffic", target: "showsTraffic")])
    let error = #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration, android: invalid,
            harmonyOS: target(style: .object, kind: .component))
    }
    #expect(error?.diagnostics.count == 2)
    #expect(error?.diagnostics.map(\.code) == ["RFMAP003", "RFMAP003"])
}
