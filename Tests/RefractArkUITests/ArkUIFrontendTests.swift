import Testing
@testable import RefractFrontend
@testable import RefractArkUI
import RefractIR

@Test func frontendParsesScrollStaticListAndLeafViews() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct StaticRows: View {
      var body: some View {
        ScrollView {
          List {
            Section("settings.general") {
              Text(verbatim: "Profile")
              Image(systemName: "gear")
            }
            Label("settings.profile", systemImage: "person")
            Divider()
            Spacer()
          }
        }
      }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let output = try ArkUIBackend().generate(module: unit.module)
    #expect(output.contains("Scroll() {"))
    #expect(output.contains("ListItemGroup({ header: Text(\"settings.general\") })"))
    #expect(output.contains("Image($r('sys.media.gear'))"))
    #expect(output.contains("Image($r('sys.media.person'))"))
    #expect(output.contains("Divider()"))
    #expect(output.contains("Blank()"))
}

@Test func frontendParsesStackAlignmentAndSpacing() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct StackLayout: View {
      var body: some View {
        VStack(alignment: .leading, spacing: 8) {
          Text(verbatim: "Profile")
          HStack(alignment: .center, spacing: 4) {
            Text(verbatim: "Enabled")
            Spacer()
          }
          ZStack(alignment: .topLeading) {
            Text(verbatim: "Background")
          }
        }
      }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let output = try ArkUIBackend().generate(module: unit.module)
    #expect(output.contains("Column({ space: 8 })"))
    #expect(output.contains(".alignItems(HorizontalAlign.Start)"))
    #expect(output.contains("Row({ space: 4 })"))
    #expect(output.contains("Stack({ alignContent: Alignment.TopStart })"))
}

@Test func frontendRejectsUnsupportedExtendedViewShapes() {
    let scrolling = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View { var body: some View { ScrollView { Text(verbatim: "One"); Text(verbatim: "Two") } } }
    """))
    #expect(scrolling.diagnostics.map(\.code) == ["RFVIEW004"])
    let image = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View { var body: some View { Image(systemName: variable) } }
    """))
    #expect(image.hasErrors)
}
