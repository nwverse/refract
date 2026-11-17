import Foundation
import Testing
import RefractIR
@testable import RefractMapping

@Test func configuredCatalogFindsImageDarkAndDensityVariants() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    for platform in Platform.allCases {
        let prefix = platform == .android ? "drawable" : "base/media"
        try writeAsset("image", at: prefix, name: "app_logo.png", in: root, platform: platform)
    }
    try writeAsset("image", at: "drawable-night", name: "app_logo.webp", in: root, platform: .android)
    try writeAsset("image", at: "dark/media", name: "app_logo.svg", in: root, platform: .harmonyOS)
    try writeAsset("image", at: "drawable-xhdpi", name: "app_logo.png", in: root, platform: .android)
    try writeAsset("image", at: "xxldpi/media", name: "app_logo.png", in: root, platform: .harmonyOS)
    let mapping = try assetMapping(in: root)
    let variants = try AssetCatalog.resolve("app_logo", kind: .image, mapping: mapping, platform: .harmonyOS)
    #expect(variants.map(\.qualifier) == ["base", "dark", "density-xhdpi"])
    #expect(variants.map(\.fileName) == ["app_logo.png", "app_logo.svg", "app_logo.png"])
    try AssetCatalog.resolveBoth("app_logo", kind: .image, mapping: mapping)
}

@Test(arguments: [
    (path: "drawable", fileName: "app_logo.ttf", kind: AssetKind.image, code: "R.asset.type_mismatch"),
    (path: "font", fileName: "app_body.svg", kind: AssetKind.font, code: "R.asset.type_mismatch"),
    (path: "font", fileName: "app_body.ttf", kind: AssetKind.raw, code: "R.asset.missing_base"),
])
func assetKindAndExtensionCannotDrift(_ case: (path: String, fileName: String, kind: AssetKind, code: String)) throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeAsset("android", at: `case`.path, name: `case`.fileName, in: root, platform: .android)
    do {
        _ = try AssetCatalog.resolve(String(`case`.fileName.split(separator: ".")[0]), kind: `case`.kind,
                                     mapping: try assetMapping(in: root), platform: .android)
        Issue.record("Expected asset validation to fail")
    } catch let error as Diagnostic {
        #expect(error.code == `case`.code)
    }
}

@Test func qualifiersMustExistInBothCatalogs() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeAsset("android", at: "drawable", name: "app_logo.png", in: root, platform: .android)
    try writeAsset("harmony", at: "base/media", name: "app_logo.png", in: root, platform: .harmonyOS)
    try writeAsset("android", at: "drawable-night", name: "app_logo.png", in: root, platform: .android)
    do {
        try AssetCatalog.resolveBoth("app_logo", kind: .image, mapping: try assetMapping(in: root))
        Issue.record("Expected cross-platform qualifier validation to fail")
    } catch let error as Diagnostic {
        #expect(error.code == "R.asset.qualifier_parity")
    }
}

@Test func rawAssetMustHaveOneMatchingUnqualifiedFile() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeAsset("raw", at: "raw", name: "privacy_policy.json", in: root, platform: .android)
    try writeAsset("raw", at: "rawfile", name: "privacy_policy.JSON", in: root, platform: .harmonyOS)
    #expect(throws: Diagnostic.self) {
        try AssetCatalog.resolveBoth("privacy_policy", kind: .raw, mapping: try assetMapping(in: root))
    }
    try FileManager.default.removeItem(at: root.appendingPathComponent("resources/rawfile/privacy_policy.JSON"))
    try writeAsset("raw", at: "rawfile", name: "privacy_policy.json", in: root, platform: .harmonyOS)
    try AssetCatalog.resolveBoth("privacy_policy", kind: .raw, mapping: try assetMapping(in: root))
}

@Test func resourceNamesAndRootsDoNotAcceptArbitraryPaths() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let mapping = try assetMapping(in: root)
    for name in ["../secret", "/etc/passwd", "nested/file", "profile photo", "Profile", ""] {
        do {
            _ = try AssetCatalog.resolve(name, kind: .image, mapping: mapping, platform: .android)
            Issue.record("Expected invalid asset name to fail")
        } catch let error as Diagnostic {
            #expect(error.code == "R.asset.invalid_name")
        }
    }
    #expect(throws: MappingError.self) {
        try Mapping.load(data: Data(mappingJSON.replacingOccurrences(of: "\"assetCatalog\": \"res\"", with: "\"assetCatalog\": \"../\"").utf8), resourceBaseURL: root)
    }
}

@Test func catalogRejectsSymlinkedAssetAndDirectory() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data("image".utf8).write(to: outside.appendingPathComponent("app_logo.png"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("res/drawable"), withDestinationURL: outside)
    do {
        _ = try AssetCatalog.resolve("app_logo", kind: .image, mapping: try assetMapping(in: root), platform: .android)
        Issue.record("Expected a symlinked catalog directory to fail")
    } catch let error as Diagnostic {
        #expect(error.code == "R.asset.missing_base")
    }
}

@Test func emptyAndExcessivelyLargeAssetsAreRejected() throws {
    let root = try temporaryAssetDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeAsset("", at: "raw", name: "privacy_policy.json", in: root, platform: .android)
    do {
        _ = try AssetCatalog.resolve("privacy_policy", kind: .raw, mapping: try assetMapping(in: root), platform: .android)
        Issue.record("Expected an empty raw asset to fail")
    } catch let error as Diagnostic {
        #expect(error.code == "R.asset.size")
    }
}

private func assetMapping(in root: URL) throws -> Mapping {
    let mapping = try Mapping.load(data: Data(mappingJSON.utf8), resourceBaseURL: root)
    #expect(mapping.android.resources.assetCatalog == "res")
    #expect(mapping.harmonyOS.resources.assetCatalog == "resources")
    return mapping
}

private let mappingJSON = """
{
  "schemaVersion": 1,
  "android": {
    "output": { "directory": "generated", "packageName": "example.generated" },
    "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
    "tokens": { "spacing": {}, "radius": {}, "font": {}, "color": {} },
    "resources": { "className": "example.app.R", "assetCatalog": "res", "strings": {} }
  },
  "harmonyOS": {
    "output": { "directory": "generated" },
    "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
    "tokens": { "spacing": {}, "radius": {}, "font": {}, "color": {} },
    "resources": { "namespace": "app", "stringTable": "string", "assetCatalog": "resources", "strings": {} }
  }
}
"""

private func temporaryAssetDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refract-assets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("res"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("resources"), withIntermediateDirectories: true)
    return root
}

private func writeAsset(_ contents: String, at directory: String, name: String, in root: URL, platform: Platform) throws {
    let url = root.appendingPathComponent(platform == .android ? "res" : "resources")
        .appendingPathComponent(directory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url.appendingPathComponent(name))
}
