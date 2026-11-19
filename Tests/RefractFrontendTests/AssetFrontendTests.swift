import Foundation
import Testing
import RefractIR
import RefractMapping
@testable import RefractFrontend

@Test func fontMustBeBodyRelativeAndCatalogNamed() throws {
    let input = #"struct AssetText: View { var body: some View { Text("assets.title").font(.custom("app_body", size: 16, relativeTo: .body)) } }"#
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: .empty)
    #expect(!unit.hasErrors)
    for name in ["../app_body", "/tmp/font", "app.body", "app-body", "AppBody"] {
        let invalid = input.replacingOccurrences(of: "app_body", with: name)
        #expect(Frontend.parse(SourceFile(path: "Input.swift", contents: invalid), mapping: .empty).hasErrors)
    }
    let invalidScale = input.replacingOccurrences(of: "relativeTo: .body", with: "relativeTo: .title")
    #expect(Frontend.parse(SourceFile(path: "Input.swift", contents: invalidScale), mapping: .empty).hasErrors)
}

@Test func rawAssetRequiresStaticNativeParameterName() throws {
    let source = """
    struct Document: RefractNativeView {
        let document: RawAsset
        var body: some View { Text(verbatim: "Policy") }
    }
    struct Screen: View {
        var body: some View { Document(document: RawAsset("../secret")) }
    }
    """
    #expect(Frontend.parse(SourceFile(path: "Input.swift", contents: source), mapping: .empty).hasErrors)
}

@Test func assetCatalogMustBeConfiguredForBothPlatforms() throws {
    let data = Data(#"{"schemaVersion":1,"android":{"output":{"directory":"generated","packageName":"example.generated"},"imports":[],"components":{},"nativeComponents":{},"modifiers":{},"tokens":{"spacing":{},"radius":{},"font":{},"color":{}},"resources":{"className":"example.app.R","assetCatalog":"res","strings":{}}},"harmonyOS":{"output":{"directory":"generated"},"imports":[],"components":{},"nativeComponents":{},"modifiers":{},"tokens":{"spacing":{},"radius":{},"font":{},"color":{}},"resources":{"namespace":"app","stringTable":"string","strings":{}}}}"#.utf8)
    #expect(throws: MappingError.self) { try Mapping.load(data: data) }
}

@Test func androidXmlImagesMustBeVectorDrawables() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refract-vector-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("res/drawable"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("resources"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let mapping = try Mapping.load(data: Data(#"{"schemaVersion":1,"android":{"output":{"directory":"generated","packageName":"example.generated"},"imports":[],"components":{},"nativeComponents":{},"modifiers":{},"tokens":{"spacing":{},"radius":{},"font":{},"color":{}},"resources":{"className":"example.app.R","assetCatalog":"res","strings":{}}},"harmonyOS":{"output":{"directory":"generated"},"imports":[],"components":{},"nativeComponents":{},"modifiers":{},"tokens":{"spacing":{},"radius":{},"font":{},"color":{}},"resources":{"namespace":"app","stringTable":"string","assetCatalog":"resources","strings":{}}}}"#.utf8), resourceBaseURL: root)
    try Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8).write(to: root.appendingPathComponent("res/drawable/app_logo.xml"))
    do {
        _ = try AssetCatalog.resolve("app_logo", kind: .image, mapping: mapping, platform: .android)
        Issue.record("Expected non-vector XML to be rejected")
    } catch let error as Diagnostic {
        #expect(error.code == "R.asset.invalid_drawable")
    }
}
