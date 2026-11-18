import Testing
import RefractCompose
import RefractArkUI
import RefractIR
import RefractMapping
import Foundation
@testable import RefractFrontend

private let formMapping: Mapping = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/form-validation/refract.json")
    return try! Mapping.load(contentsOf: url)
}()

private let signupSource = """
protocol SignupModel: RefractModel {
    var submitting: Bool { get }
    @refractText var submissionError: String { get }
    @refractAsync func submit(email: String, password: String, confirmation: String)
    @refractAsync func retry(email: String, password: String, confirmation: String)
}
struct SignupScreen: View {
    let model: SignupModel
    @State private var form = refractForm {
        Field("email", initial: "", rules: .nonEmpty)
        Field("password", initial: "", rules: [.nonEmpty, .equals("confirmation")])
        Field("confirmation", initial: "")
    }
    var body: some View {
        Form {
            TextField("settings.email", text: $form.email)
            if model.submitting {
                Text(verbatim: "Submitting")
            }
            if refractPresent(model.submissionError) {
                Text(model.submissionError)
            }
            Button("settings.submit") {
                form.submit(model.submit)
            }
            .disabled(model.submitting)
            Button("settings.retry") {
                form.submit(model.retry)
            }
        } (form: $form)
    }
}
"""

@Test func formLowersDraftRulesAndGuardedSubmissionOnBothBackends() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: signupSource))
    #expect(unit.diagnostics.isEmpty)
    let model = try #require(unit.module.models.first)
    #expect(model.actions.map(\.effect) == [.asyncAttempt, .asyncAttempt])
    #expect(model.properties.first(where: { $0.name == "submissionError" })?.effect == .text)
    let form = try #require(unit.module.screens.first?.states.compactMap { state -> FormDeclaration? in
        guard case let .form(_, declaration, _) = state else { return nil }
        return declaration
    }.first)
    #expect(form.fields.map(\.name) == ["email", "password", "confirmation"])
    #expect(form.fields[1].rules == [.nonEmpty, .equals("confirmation")])

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: formMapping)
    #expect(kotlin.contains("var formEmail by remember { mutableStateOf(\"\") }"))
    #expect(kotlin.contains("public fun submit(email: String, password: String, confirmation: String): Boolean"))
    #expect(kotlin.contains("public val submissionError: State<String?>"))
    #expect(kotlin.contains("formPassword == formConfirmation"))
    #expect(kotlin.contains("model.submit(email = formEmail, password = formPassword, confirmation = formConfirmation)"))
    #expect(kotlin.contains("model.retry(email = formEmail, password = formPassword, confirmation = formConfirmation)"))
    #expect(kotlin.contains("enabled = !(model.submitting.value)"))
    #expect(kotlin.contains("if (model.submissionError.value != null)"))
    #expect(!kotlin.contains("Validator"))
    #expect(!kotlin.contains("object : SignupModel"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: formMapping)
    #expect(ark.contains("@Local private formEmail: string = '';"))
    #expect(ark.contains("submit(email: string, password: string, confirmation: string): boolean;"))
    #expect(ark.contains("submissionError: string | null | undefined;"))
    #expect(ark.contains("this.formPassword === this.formConfirmation"))
    #expect(ark.contains("this.model.submit(this.formEmail, this.formPassword, this.formConfirmation);"))
    #expect(ark.contains(".enabled(!(this.model.submitting))"))
}

@Test func formBindingOwnershipLowersToValueAndCallbackParameters() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SignupModel: RefractModel {
        @refractAsync func submit(email: String)
    }
    struct SignupScreen: View {
        let model: SignupModel
        @Binding var form: RefractForm = refractForm {
            Field("email", initial: "", rules: .nonEmpty)
        }
        var body: some View {
            Form {
                TextField("settings.email", text: $form.email)
                Button("settings.submit") { form.submit(model.submit) }
            } (form: $form)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: formMapping)
    #expect(kotlin.contains("formEmail: String,"))
    #expect(kotlin.contains("onFormEmailChange: (String) -> Unit,"))
    #expect(kotlin.contains("onValueChange = onFormEmailChange,"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: formMapping)
    #expect(ark.contains("@Require @Param formEmail: string;"))
    #expect(ark.contains("@Event onFormEmailChange: (value: string) => void"))
    #expect(ark.contains("this.onFormEmailChange(value);"))
}

@Test func formRejectsUnknownRulesMismatchedEqualityAndSubmitShapes() throws {
    let unknown = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var form = refractForm {
            Field("email", initial: "", rules: [.nonEmpty, .matches(".*")])
        }
        var body: some View { Form { Text(verbatim: "x") } (form: $form) }
    }
    """))
    #expect(unknown.diagnostics.map(\.code) == ["RFFORM002"])

    let equality = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var form = refractForm {
            Field("password", initial: "", rules: .equals("missing"))
        }
        var body: some View { Form { Text(verbatim: "x") } (form: $form) }
    }
    """))
    #expect(equality.diagnostics.map(\.code) == ["RFFORM003"])

    let missingField = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol M: RefractModel {
        @refractAsync func submit(email: String, password: String)
    }
    struct Screen: View {
        let model: M
        @State private var form = refractForm {
            Field("email", initial: "")
        }
        var body: some View { Form { Button("settings.submit") { form.submit(model.submit) } } (form: $form) }
    }
    """))
    #expect(missingField.diagnostics.map(\.code) == ["RFFORM004"])

    let presence = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol M: RefractModel {
        var submitting: Bool { get }
    }
    struct Screen: View {
        let model: M
        var body: some View { VStack { if refractPresent(model.submitting) { Text(verbatim: "x") } } }
    }
    """))
    #expect(presence.diagnostics.map(\.code) == ["RFFORM006"])

    let unknownField = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var form = refractForm {
            Field("email", initial: "")
        }
        var body: some View { Form { Text(form.password) } (form: $form) }
    }
    """))
    #expect(unknownField.diagnostics.map(\.code).contains("RFFORM002"))
}

@Test func modelEffectsAreTypedBoundariesNotArbitraryAttributes() throws {
    let invalid = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol M: RefractModel {
        @refractText var count: Int { get }
    }
    """))
    #expect(invalid.diagnostics.map(\.code) == ["model.invalid_property"])

    let unsupported = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol M: RefractModel {
        @available(iOS 17, *) var title: String { get }
    }
    """))
    #expect(unsupported.diagnostics.map(\.code) == ["model.invalid_property"])

    let async = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol M: RefractModel {
        func refresh() async
    }
    """))
    #expect(async.diagnostics.map(\.code) == ["model.invalid_action"])
}
