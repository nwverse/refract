import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendParsesSecureFieldObscuredByDefault() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        var body: some View { SecureField("settings.password", text: $password) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .secureInput(placeholder, value, reveal, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a secure input")
        return
    }
    #expect(placeholder?.value == .localizedText(LocalizedText(key: "settings.password")))
    #expect(value.value == .valueProperty(.state("password")))
    #expect(reveal == nil)
}

@Test func frontendParsesSecureFieldWithRevealModifier() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        @State private var isRevealed: Bool = false
        var body: some View {
            SecureField("settings.password", text: $password)
                .secureReveal($isRevealed)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .secureInput(_, _, reveal, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a secure input")
        return
    }
    #expect(reveal?.value == .valueProperty(.state("isRevealed")))
    #expect(reveal?.type == .bool)
}

@Test func frontendParsesSecureFieldWithBindingReveal() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        @Binding var isRevealed: Bool
        var body: some View {
            SecureField("settings.password", text: $password)
                .secureReveal($isRevealed)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .secureInput(_, _, reveal, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a secure input")
        return
    }
    #expect(reveal?.value == .valueProperty(.binding("isRevealed")))
}

@Test func frontendRejectsSecureRevealWithLiteral() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        var body: some View {
            SecureField("settings.password", text: $password)
                .secureReveal(.constant(true))
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFSECURE001" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsSecureRevealAppliedTwice() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        @State private var a: Bool = false
        @State private var b: Bool = false
        var body: some View {
            SecureField("settings.password", text: $password)
                .secureReveal($a)
                .secureReveal($b)
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFSECURE001" })
}

@Test func frontendRejectsSecureRevealOnOtherViews() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Row: View {
        @State private var name: String = ""
        @State private var isRevealed: Bool = false
        var body: some View {
            TextField("settings.display.name", text: $name)
                .secureReveal($isRevealed)
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFSECURE001" })
}

@Test func frontendRejectsSecureFieldWithLiteralSecret() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        var body: some View { SecureField("settings.password", text: "hunter2") }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFSECURE002" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsSecureFieldWithNonCanonicalTitle() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PasswordRow: View {
        @State private var password: String = ""
        var body: some View { SecureField("Password", text: $password) }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFSECURE002" })
}
