import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendBuildsMinimalViews() throws {
    let source = SourceFile(path: "Input.swift", contents: """
    struct Hello: View {
        var body: some View {
            VStack {
                Text("hello.title")
                HStack { Button("hello.go") { } }
            }
        }
    }
    """)
    let unit = Frontend.parse(source)
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first)
    guard case let .stack(axis, children, _, _) = screen.body else {
        Issue.record("Expected VStack")
        return
    }
    #expect(axis == .vertical)
    #expect(children.count == 2)
}

@Test func frontendRejectsUnknownViewWithCodedDiagnostic() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View { var body: some View { Gauge("photo") } }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
}
