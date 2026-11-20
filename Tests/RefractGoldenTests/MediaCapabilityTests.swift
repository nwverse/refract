import Foundation
import Testing
import RefractFrontend
import RefractIR
import RefractGolden

private let mediaRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func mediaFixture(_ name: String) throws -> FixtureCase {
    try CorpusLoader.load(repository: mediaRepository).first { $0.name == name }!
}

@Test func mediaCapabilitiesUseClosedTypedComponentsOnBothBackends() throws {
    let generated = try GoldenRunner.generate(mediaFixture("interop-media-capabilities"))
    #expect(GoldenRunner.differences(for: try mediaFixture("interop-media-capabilities"), result: generated) == [])
    let kotlin = try #require(generated.kotlin)
    let arkTS = try #require(generated.arkTS)
    for capability in ["Playback", "Camera", "Share"] {
        #expect(kotlin.contains("Native\(capability)Capability(identifier = identifier, revision = revision, onCancel = { model.cancel\(capability)() })"))
        #expect(arkTS.contains("Native\(capability)Capability({ identifier: this.identifier, revision: this.revision, onCancel: () => { this.model.cancel\(capability)(); } })"))
        for state in ["unavailable", "permissionRequired", "permissionDenied", "approvalRequired", "ready", "cancelled"] {
            #expect(kotlin.contains("\(capability)CapabilityState.\(state)"))
            #expect(arkTS.contains("\(capability)CapabilityState.\(state)"))
        }
    }
    for forbidden in ["androidx.camera", "android.content.Intent", "MediaPlayer", "AVPlayer", "http://", "https://", "refract.runtime"] {
        #expect(!kotlin.contains(forbidden))
        #expect(!arkTS.contains(forbidden))
    }
}

@Test func mediaRejectsUndeclaredRecipientPayloadBeforeEitherBackendWrites() throws {
    let generated = try GoldenRunner.generate(mediaFixture("interop-media-capability-reject"))
    #expect(generated.kotlin == nil && generated.arkTS == nil)
    #expect(generated.diagnostics.map(\.code) == ["RFNATIVE002"])
    #expect(generated.renderedDiagnostics.contains("recipient"))
    #expect(GoldenRunner.differences(for: try mediaFixture("interop-media-capability-reject"), result: generated) == [])
}

@Test func mediaCapabilityStatesCannotSilentlyOmitAbsence() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum CameraCapabilityState {
        case unavailable
        case permissionRequired
        case permissionDenied
        case approvalRequired
        case ready
        case cancelled
    }
    struct CameraCapabilityScreen: View {
        let state: CameraCapabilityState
        var body: some View {
            switch state {
            case .ready: Text(verbatim: "App-owned camera surface")
            case .cancelled: Text(verbatim: "Cancelled")
            }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFCTRL007"])
    #expect(unit.diagnostics[0].rendered.contains("unavailable"))
}

@Test func mediaPermissionCannotBecomeAnArbitraryNativeClosure() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NativeCameraCapability: RefractNativeView {
        let onCancel: () -> Void
        var body: some View { Button("media.camera.cancel") { onCancel() } }
    }
    struct CameraCapabilityScreen: View {
        var body: some View {
            NativeCameraCapability(onCancel: { requestSystemPermission() })
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code).contains("RFNATIVE002"))
}
