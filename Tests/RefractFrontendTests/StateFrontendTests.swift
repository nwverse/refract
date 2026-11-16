import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendCapturesLocalStateReadAndIncrement() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Counter: View {
        @State private var count: Int = 0
        var body: some View {
            VStack {
                Text(verbatim: "Count: \\(count)")
                Button(verbatim: "Increment") { count += 1 }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first)
    guard case let .state(name, type, _, _) = screen.states.first else {
        Issue.record("Expected local state")
        return
    }
    #expect(name == "count")
    #expect(type == .int)
    guard case let .stack(_, children, _, _) = screen.body,
          case let .text(text, _, _) = children[0],
          case let .button(_, action, _, _) = children[1],
          case let .interpolatedString(segments) = text.value else {
        Issue.record("Expected a stateful counter")
        return
    }
    #expect(segments.count == 3)
    #expect(segments[0] == .literal("Count: "))
    #expect(segments[2] == .literal(""))
    guard case let .expression(read) = segments[1] else {
        Issue.record("Expected a state read in interpolation")
        return
    }
    #expect(read.value == .valueProperty(.state("count")))
    guard case let .increment(.state("count"), amount) = action else {
        Issue.record("Expected a local state increment")
        return
    }
    #expect(amount.value == .numberLiteral("1"))
}

@Test func frontendCapturesParentBindingReadAndWrite() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct EnabledRow: View {
        @Binding var isEnabled: Bool
        var body: some View {
            VStack {
                Text("Enabled: \\(isEnabled)")
                Button("Disable") { isEnabled = false }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first)
    guard case let .binding(bindingName, bindingType, bindingLocation) = screen.states.first else {
        Issue.record("Expected a parent binding")
        return
    }
    #expect(bindingName == "isEnabled")
    #expect(bindingType == .bool)
    #expect(bindingLocation?.line == 2)
    guard case let .stack(_, children, _, _) = screen.body,
          case let .text(text, _, _) = children[0],
          case let .button(_, action, _, _) = children[1],
          case let .interpolatedString(segments) = text.value,
          case let .expression(read) = segments[1] else {
        Issue.record("Expected a binding read and write")
        return
    }
    #expect(read.value == .valueProperty(.binding("isEnabled")))
    guard case let .assign(.binding("isEnabled"), value) = action else {
        Issue.record("Expected a binding assignment")
        return
    }
    #expect(value.value == .boolLiteral(false))
    #expect(value.location != nil)
}

@Test(arguments: [
    "@ObservedObject var model: SettingsModel",
    "@State private var count: Int",
])
func frontendRejectsUnsupportedStoredProperties(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Unsupported: View {
        \(declaration)
        var body: some View { Text(verbatim: "Unsupported") }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["state.invalid_declaration"])
    #expect(unit.module.screens.isEmpty)
}
