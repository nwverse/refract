import Foundation
import Testing
@testable import RefractIR

@Test func nativeHostContractsAndSelectedEventsRoundTrip() throws {
    let host = NativeHostContract(name: "SyncHost", capability: .backgroundWork, actions: [
        ModelAction(name: "schedule", parameters: NativeHostCapability.backgroundWork.parameters),
        ModelAction(name: "cancel", parameters: NativeHostCapability.backgroundWork.parameters),
        ModelAction(name: "confirm", parameters: NativeHostCapability.backgroundWork.parameters),
    ])
    let value = NativeValueReference(propertyName: "event", kind: .backgroundWorkEvent, selectedField: .id)
    let action = StateAction.hostMethod(host: "work", capability: .backgroundWork, name: "cancel", arguments: [
        ActionArgument(label: nil, value: Expression(.nativeValueProperty(NativeValueProperty(value: "event", field: .id)), type: .string)),
        ActionArgument(label: "revision", value: Expression(.nativeValueProperty(NativeValueProperty(value: "event", field: .revision)), type: .int)),
    ])
    let module = Module(sourceFile: "Input.swift", screens: [Screen(name: "SyncScreen", states: [
        .nativeHost(NativeHostReference(propertyName: "work", protocolName: "SyncHost", capability: .backgroundWork), location: nil),
    ], body: .button(label: .text(Expression(.verbatimText("Cancel")), modifiers: [], location: nil),
                     action: action, modifiers: [], location: nil), nativeValues: [value])], nativeHosts: [host])
    let encoded = try JSONEncoder().encode(module)
    let decoded = try JSONDecoder().decode(Module.self, from: encoded)
    #expect(decoded.screens.map(\.nativeValues) == module.screens.map(\.nativeValues))
    #expect(decoded.nativeHosts == module.nativeHosts)
    #expect(decoded == module)
    #expect(NativeValueKind.notificationEvent.states.contains("unavailable"))
    #expect(NativeValueKind.notificationEvent.states.contains("stale"))
    #expect(NativeValueKind.backgroundWorkEvent.states.contains("confirmationRequired"))
}
