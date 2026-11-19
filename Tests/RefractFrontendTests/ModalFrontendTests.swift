import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let modalRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func screenRoundTripRetainsModalAndNavigationOperations() throws {
    let modal = ModalPresentation(kind: .sheet, stateName: "visible", isBinding: false,
                                  content: [.text(Expression(.verbatimText("Sheet")), modifiers: [], location: nil)])
    let screen = Screen(name: "Screen", modals: [modal], navigation: NavigationOperation(enumName: "Route"),
                        body: .text(Expression(.verbatimText("Root")), modifiers: [], location: nil))
    let module = Module(sourceFile: "Input.swift", screens: [screen])
    let decoded = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(module))
    #expect(decoded == module)
}

@Test func nativeModalHostsOwnPresentationAndTypedDismissal() throws {
    let fixture = modalRepository.appendingPathComponent("Fixtures/modal-native-host")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(try String(contentsOf: fixture.appendingPathComponent("refract.json"), encoding: .utf8).utf8),
                                  file: "refract.json", resourceBaseURL: fixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    guard let screen = unit.module.screens.first(where: { $0.name == "ModalHostScreen" }) else {
        Issue.record("Missing the generated modal host")
        return
    }
    #expect(screen.modals.map(\.kind) == [.sheet, .alert])
    #expect(screen.modals.map(\.isBinding) == [true, true])
    #expect(screen.body.children.isEmpty == false)

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("ModalBottomSheet(onDismissRequest = { onIsProfilePresentedChange(false) })"))
    #expect(kotlin.contains("LaunchedEffect(Unit)"))
    #expect(kotlin.contains("onDismissRequest = { onShowDeleteConfirmationChange(false) }"))
    #expect(kotlin.contains("onShowDeleteConfirmationChange(false)\n                    model.confirmDelete()"))

    #expect(kotlin.contains("onShowDeleteConfirmationPresent: () -> Unit = {}"))
    #expect(kotlin.contains("@OptIn(ExperimentalMaterial3Api::class)"))
    #expect(kotlin.contains("ProfileSheet(model = model)"))
    #expect(!kotlin.contains("onBackPressed"))
    #expect(!kotlin.contains("Overlay"))
    #expect(!kotlin.contains("Registry"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains(".bindSheet(this.isProfilePresented, this.isProfilePresentedSheetContent(), {"))
    #expect(ark.contains("@Builder isProfilePresentedSheetContent()"))
    #expect(ark.contains("onWillDismiss: (action: DismissSheetAction): void => {"))
    #expect(ark.contains("action.dismiss();"))
    #expect(ark.contains("this.onIsProfilePresentedChange(false);"))
    #expect(ark.contains("@Require @Param showDeleteConfirmation: boolean;"))
    #expect(ark.contains("this.onShowDeleteConfirmationChange(true);"))
    #expect(ark.contains("@Event onShowDeleteConfirmationPresent: () => void"))

    #expect(ark.contains("this.onShowDeleteConfirmationPresent();"))
    #expect(ark.contains("@Monitor('showDeleteConfirmation')"))
    #expect(ark.contains("aboutToAppear(): void"))
    #expect(!ark.contains("AlertDialog.show"))
    #expect(!ark.contains("@Entry"))
}

@Test func localAlertUsesTheSameTypedNativeHostEvent() throws {
    let source = """
    protocol Model: RefractModel { func confirm() }
    struct LocalAlertScreen: View {
        let model: Model
        @State private var showConfirmation: Bool = false
        var body: some View {
            VStack {
                Button("modal.delete.open") { showConfirmation = true }
            }
            .alert("modal.delete.title", isPresented: $showConfirmation) {
                    Button("modal.delete.confirm") { model.confirm() }
                    Button("modal.delete.cancel", role: .cancel) {}
                } message: { Text("modal.delete.message") }
        }
    }
    """
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.screens.first?.modals.map(\.isBinding) == [false])
    let fixture = modalRepository.appendingPathComponent("Fixtures/modal-native-host")
    let mapping = try Mapping.load(data: Data(try String(contentsOf: fixture.appendingPathComponent("refract.json"), encoding: .utf8).utf8),
                                  file: "refract.json", resourceBaseURL: fixture)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("var showConfirmation by remember { mutableStateOf(false) }"))
    #expect(kotlin.contains("if (showConfirmation)"))
    #expect(kotlin.contains("onShowConfirmationPresent()"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Local private showConfirmation: boolean = false;"))
    #expect(ark.contains("@Monitor('showConfirmation')"))
    #expect(ark.contains("this.onShowConfirmationPresent();"))
}

@Test func localSheetRetainsRootModifierOrderAndNativeHost() throws {
    let fixture = modalRepository.appendingPathComponent("Fixtures/modal-sheet-state")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(try String(contentsOf: fixture.appendingPathComponent("refract.json"), encoding: .utf8).utf8),
                                  file: "refract.json", resourceBaseURL: fixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("modifier.padding(all = 16.dp).padding(all = 8.dp)"))
    #expect(kotlin.contains("ModalBottomSheet(onDismissRequest = { showDetails = false })"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("}.padding(16).padding(8)\n    .bindSheet(this.showDetails"))
    #expect(ark.contains("@Builder showDetailsSheetContent()"))
}

@Test(arguments: [
    ("modal-reject-item", "RFMODAL001"),
    ("modal-reject-owner", "RFMODAL001"),
    ("modal-reject-alert", "RFMODAL002"),
])
func unsupportedModalInputIsAnAtomicDiagnostic(_ fixture: String, _ code: String) throws {
    let input = try String(contentsOf: modalRepository.appendingPathComponent("Fixtures/\(fixture)/Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.contains(where: { $0.code == code }))
    #expect(unit.module.screens.isEmpty)
}

@Test func aNativeModalCannotShareItsBooleanOwner() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { func confirm() }
    struct Screen: View {
        let model: Model
        @State private var visible: Bool = false
        var body: some View {
            Text(verbatim: "Root")
                .sheet(isPresented: $visible) { Text(verbatim: "Sheet") }
                .alert("modal.title", isPresented: $visible) {
                    Button("modal.confirm") { model.confirm() }
                    Button("modal.cancel", role: .cancel) {}
                } message: { Text("modal.message") }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFMODAL003" }))
}

@Test func manuallyConstructedModalCannotEscapeTypedDismissal() {
    let modal = ModalPresentation(kind: .sheet, stateName: "missing", isBinding: false,
                                  content: [.text(Expression(.verbatimText("Content")), modifiers: [], location: nil)])
    let screen = Screen(name: "Screen", modals: [modal],
                        body: .text(Expression(.verbatimText("Root")), modifiers: [], location: nil))
    let module = Module(sourceFile: "Input.swift", screens: [screen])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: module) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: module) }
}
