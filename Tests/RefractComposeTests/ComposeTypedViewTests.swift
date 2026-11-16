import Foundation
import Testing
import RefractFrontend
import RefractIR
import RefractMapping
@testable import RefractCompose

@Test func composeLowersTypedLayoutFromFrontend() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct TypedLayout: View {
        var body: some View {
            VStack(alignment: .leading, spacing: .medium) {
                List { Text("settings.profile") }
                HStack { Text(verbatim: "Enabled"); Spacer(); Divider() }
                HStack { Text(verbatim: "Default spacing") }
            }.padding(16)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/compose-typed-layout/refract.json")
    let mapping = try Mapping.load(contentsOf: fixture)
    let output = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(output.contains("horizontalAlignment = Alignment.Start"))
    #expect(output.contains("verticalArrangement = Arrangement.spacedBy(8.dp)"))
    #expect(output.components(separatedBy: "Row(modifier = Modifier) {").count == 3)
    #expect(output.contains("item(key = \"row:settings.profile\", contentType = \"Text\")"))
    #expect(output.contains("Spacer(modifier = Modifier.weight(1f))"))
    #expect(output.contains("VerticalDivider(modifier = Modifier)"))
    #expect(!output.contains("import androidx.compose.foundation.layout.weight"))
    #expect(output.contains("import refract.generated.R\n"))
    #expect(output.components(separatedBy: "import refract.").count == 2)
}

@Test func composeRejectsSystemImageWithStableCode() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct BadImage: View { var body: some View { Image(systemName: "gear") } }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module)
    }
    #expect(diagnostic?.code == "RF-C002")
}

@Test func composeRejectsNestedVerticalScrollingList() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct BadList: View { var body: some View { ScrollView { List { Text(verbatim: "Row") } } } }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module)
    }
    #expect(diagnostic?.code == "RF-C004")
}

@Test func composeRejectsLabelWithoutNativeIconContract() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct BadLabel: View { var body: some View { Label(verbatim: "Profile", systemImage: "person") } }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module)
    }
    #expect(diagnostic?.code == "RF-C002")
}

@Test func composeRejectsDuplicateStaticTextKeys() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct DuplicateRows: View {
        var body: some View { List { Text("settings.profile"); Text("settings.profile") } }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module, mapping: try layoutMapping())
    }
    #expect(diagnostic?.code == "RF-C003")
}

@Test func composeRejectsStaticRowWithoutExplicitIdentity() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct UnidentifiedRow: View { var body: some View { List { Divider() } } }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module)
    }
    #expect(diagnostic?.code == "RF-C003")
}

@Test func composeRejectsDrawableWithoutResourceClass() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct ImageWithoutMapping: View { var body: some View { Image("profile_photo") } }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: unit.module)
    }
    #expect(diagnostic?.code == "RF-C002")
}

@Test func composeUsesConfiguredResourceAndPackage() throws {
    let mapping = Mapping(android: PlatformMapping(
        output: Output(directory: "android", packageName: "example.generated"),
        resources: Resources(className: "example.app.R")
    ))
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct TypedImage: View { var body: some View { Image("profile_photo") } }
    """))
    let output = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(output.contains("package example.generated"))
    #expect(output.contains("import example.app.R"))
    #expect(output.contains("painterResource(R.drawable.profile_photo)"))
}

private func layoutMapping() throws -> Mapping {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/compose-typed-layout/refract.json")
    return try Mapping.load(contentsOf: fixture)
}
