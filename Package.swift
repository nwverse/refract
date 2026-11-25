// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "refract",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RefractIR", targets: ["RefractIR"]),
        .library(name: "RefractFrontend", targets: ["RefractFrontend"]),
        .library(name: "RefractMapping", targets: ["RefractMapping"]),
        .library(name: "RefractCompose", targets: ["RefractCompose"]),
        .library(name: "RefractArkUI", targets: ["RefractArkUI"]),
        .executable(name: "refract", targets: ["RefractCLI"]),
        .library(name: "RefractGolden", targets: ["RefractGolden"]),
        .plugin(name: "RefractSwiftPMPlugin", targets: ["RefractBuildTool"]),
        .plugin(name: "RefractGenerate", targets: ["RefractGenerate"]),
        .plugin(name: "RefractCheck", targets: ["RefractCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "600.0.1"),
    ],
    targets: [
        .target(
            name: "RefractIR",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(
            name: "RefractFrontend",
            dependencies: [
                "RefractIR",
                "RefractMapping",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(
            name: "RefractMapping",
            dependencies: ["RefractIR"],
            resources: [.process("Resources")]
        ),
        .target(name: "RefractCompose", dependencies: ["RefractIR", "RefractMapping"]),
        .target(name: "RefractArkUI", dependencies: ["RefractIR", "RefractMapping"]),
        .target(name: "RefractOutput"),
        .executableTarget(
            name: "RefractCLI",
            dependencies: ["RefractIR", "RefractFrontend", "RefractMapping", "RefractCompose", "RefractArkUI", "RefractOutput"]
        ),
        .plugin(
            name: "RefractGenerate",
            capability: .command(
                intent: .custom(verb: "refract-generate", description: "Regenerate committed native sources"),
                permissions: [.writeToPackageDirectory(reason: "Refract publishes reviewed Kotlin and ArkTS sources only when explicitly requested.")]
            ),
            dependencies: ["RefractConsumerTool", "RefractCLI"]
        ),
        .plugin(
            name: "RefractCheck",
            capability: .command(
                intent: .custom(verb: "refract-check", description: "Verify committed native sources without writing")
            ),
            dependencies: ["RefractConsumerTool", "RefractCLI"]
        ),
        .plugin(
            name: "RefractBuildTool",
            capability: .buildTool(),
            dependencies: ["RefractConsumerTool", "RefractCLI"]
        ),
        .executableTarget(name: "RefractConsumerTool"),
        .testTarget(name: "RefractIRTests", dependencies: ["RefractIR"]),
        .testTarget(name: "RefractFrontendTests", dependencies: ["RefractFrontend", "RefractCompose", "RefractArkUI", "RefractGolden"]),
        .testTarget(
            name: "RefractMappingTests",
            dependencies: ["RefractMapping"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "RefractComposeTests",
            dependencies: ["RefractCompose", "RefractFrontend", "RefractMapping"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "RefractArkUITests",
            dependencies: ["RefractArkUI", "RefractFrontend", "RefractCompose"],
            exclude: ["Fixtures"]
        ),
        .testTarget(name: "RefractCLITests", dependencies: ["RefractOutput"]),
        .testTarget(name: "RefractGoldenTests", dependencies: ["RefractGolden"]),
        .target(
            name: "RefractGolden",
            dependencies: ["RefractFrontend", "RefractMapping", "RefractCompose", "RefractArkUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
