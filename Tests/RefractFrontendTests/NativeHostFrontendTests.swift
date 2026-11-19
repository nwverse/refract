import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let nativeHostRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func nativeFixture(_ name: String) throws -> (TranslationUnit, Mapping) {
    let directory = nativeHostRepository.appendingPathComponent("Fixtures/\(name)")
    let source = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(contentsOf: directory.appendingPathComponent("refract.json"))
    return (Frontend.parse(SourceFile(path: "Input.swift", contents: source), mapping: mapping), mapping)
}

@Test(arguments: ["interop-native-lifecycle", "interop-native-notification", "interop-native-background-work"])
func nativeHostContractsGenerateBothBackends(_ name: String) throws {
    let (unit, mapping) = try nativeFixture(name)
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first)
    #expect(screen.nativeValues.count >= 1)
    #expect(unit.module.nativeHosts.count == 1)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(!kotlin.contains("NotificationManager"))
    #expect(!kotlin.contains("WorkManager"))
    #expect(!ark.contains("notificationManager"))
    #expect(!ark.contains("workScheduler"))
    #expect(!kotlin.contains("object :"))
    #expect(!ark.contains("@Entry"))
    if name == "interop-native-lifecycle" {
        #expect(kotlin.contains("DisposableEffect(Unit)"))
        #expect(kotlin.contains("lifecycle.foreground()"))
        #expect(kotlin.contains("lifecycle.background()"))
        #expect(ark.contains("aboutToAppear()"))
        #expect(ark.contains("aboutToDisappear()"))
    } else {
        #expect(kotlin.contains("id: String, revision: Int"))
        #expect(kotlin.contains("correlation.revision"))
        #expect(kotlin.contains("State.unavailable"))
        #expect(kotlin.contains("State.stale"))
        #expect(kotlin.contains("State.cancelled"))
        #expect(kotlin.contains("State.confirmationRequired"))
        #expect(ark.contains("id: string;"))
        #expect(ark.contains("revision: number;"))
        #expect(ark.contains("this.correlation.revision"))
    }
}

@Test func nativeHostRolesRejectMissingCorrelationAndExecutionReceipt() {
    let source = """
    protocol Host: RefractNotificationHost {
        func present(_ id: String, revision: Int) -> Bool
        func cancel(_ id: String, revision: Int)
        func confirm(_ id: String, revision: Int)
    }
    struct Screen: View {
        let host: Host
        var body: some View { Text(verbatim: "Invalid") }
    }
    """
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.map(\.code).contains("RFHOST002"))
    #expect(unit.module.screens.isEmpty)
}

@Test(arguments: [
    ("protocol Host: RefractNotificationHost { func present(_ id: String, revision: Int); func cancel(_ id: String, revision: Int); func confirm(_ id: String, revision: Int) }", "RFHOST004"),
    ("protocol Host: RefractLifecycleHost { func foreground(); func background() }", "RFHOST003"),
])
func nativeHostInputMustBindItsClosedContract(_ declaration: String, _ expected: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    \(declaration)
    struct Screen: View {
        let host: Host
        var body: some View { Text(verbatim: "Missing event") }
    }
    """))
    #expect(unit.diagnostics.map(\.code).contains(expected))
    #expect(unit.module.screens.isEmpty)
}

@Test func nativeHostRequestCannotInventARevision() {
    let source = """
    protocol Host: RefractNotificationHost {
        func present(_ id: String, revision: Int)
        func cancel(_ id: String, revision: Int)
        func confirm(_ id: String, revision: Int)
    }
    struct Screen: View {
        let host: Host
        @RefractNativeValue var event: RefractNotificationEvent
        var body: some View {
            VStack {
                switch event {
                case .unavailable: Text(verbatim: "Unavailable")
                case .accepted: Text(verbatim: "Accepted")
                case .scheduled: Text(verbatim: "Scheduled")
                case .delivered: Text(verbatim: "Delivered")
                case .cancelled: Text(verbatim: "Cancelled")
                case .stale: Text(verbatim: "Stale")
                case .confirmationRequired: Text(verbatim: "Confirm")
                case .confirmed: Text(verbatim: "Confirmed")
                }
                Button("synthetic.request") { host.present(event.id, revision: 1) }
            }.refractNativeValue(event.state)
        }
    }
    """
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.map(\.code).contains("RFHOST005"))
    #expect(unit.module.screens.isEmpty)
}

@Test func nativeHostEventSwitchCannotSkipTerminalStates() {
    let source = """
    protocol Host: RefractBackgroundWorkHost {
        func schedule(_ id: String, revision: Int)
        func cancel(_ id: String, revision: Int)
        func confirm(_ id: String, revision: Int)
    }
    struct Screen: View {
        let host: Host
        @RefractNativeValue var event: RefractBackgroundWorkEvent
        var body: some View {
            VStack {
                switch event {
                case .accepted:
                    Text(verbatim: "Accepted")
                }
            }.refractNativeValue(event.state)
        }
    }
    """
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.map(\.code).contains("RFCTRL007"))
    #expect(unit.module.screens.isEmpty)
}
