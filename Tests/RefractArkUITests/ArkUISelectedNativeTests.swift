import Foundation
import Testing
@testable import RefractArkUI
@testable import RefractCompose
@testable import RefractFrontend
import RefractIR
import RefractMapping

private let selectedNativeSource = """
import SwiftUI

struct AppleBadge: RefractNativeView {
    var body: some View { Text("Native") }
}
struct AndroidBadge: RefractNativeView {
    var body: some View { Text("Native") }
}
struct HarmonyBadge: RefractNativeView {
    var body: some View { Text("Native") }
}
struct PlatformNativeScreen: View {
    var body: some View {
        refractView(
            ios: { AppleBadge() },
            android: { AndroidBadge() },
            harmonyOS: { HarmonyBadge() }
        )
    }
}
"""

private let selectedNativeMapping = """
{
  "version": 1,
  "nativeComponents": [
    {
      "swift": "AndroidBadge",
      "android": { "kind": "composable", "symbol": "AndroidBadge", "module": "example.android", "parameters": [] },
      "harmonyOS": { "kind": "component", "symbol": "AndroidBadge", "module": "example.android", "parameters": [] }
    },
    {
      "swift": "HarmonyBadge",
      "android": { "kind": "composable", "symbol": "HarmonyBadge", "module": "example.harmony", "parameters": [] },
      "harmonyOS": { "kind": "component", "symbol": "HarmonyBadge", "module": "example.harmony", "parameters": [] }
    }
  ]
}
"""

@Test func unselectedNativeBranchNeedsNoMappingOrImport() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: selectedNativeSource))
    #expect(unit.diagnostics.isEmpty)
    let mapping = try Mapping.load(data: Data(selectedNativeMapping.utf8))
    let harmony = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(harmony.contains("HarmonyBadge({  })"))
    #expect(!harmony.contains("AppleBadge"))
    #expect(!harmony.contains("AndroidBadge"))
    #expect(harmony.contains("import { HarmonyBadge } from 'example.harmony';"))

    let android = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(android.contains("AndroidBadge()"))
    #expect(!android.contains("AppleBadge"))
    #expect(!android.contains("HarmonyBadge"))
}

@Test func selectedNativeBranchStillRequiresItsMapping() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: selectedNativeSource))
    #expect(unit.diagnostics.isEmpty)
    #expect(throws: (any Error).self) {
        try ArkUIBackend().generate(module: unit.module, mapping: .empty)
    }
    #expect(throws: (any Error).self) {
        try ComposeBackend().generate(module: unit.module, mapping: .empty)
    }
}
