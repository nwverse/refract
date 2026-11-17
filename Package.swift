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
        .testTarget(name: "RefractIRTests", dependencies: ["RefractIR"]),
        .testTarget(name: "RefractFrontendTests", dependencies: ["RefractFrontend", "RefractCompose", "RefractArkUI", "RefractGolden"]),
        .testTarget(
            name: "RefractMappingTests",
            dependencies: ["RefractMapping"],
            exclude: ["Fixtures"]
        ),
        .testTarget(name: "RefractComposeTests", dependencies: ["RefractCompose", "RefractFrontend", "RefractMapping"]),
        .testTarget(name: "RefractArkUITests", dependencies: ["RefractArkUI", "RefractFrontend", "RefractCompose"]),
        .testTarget(name: "RefractCLITests", dependencies: ["RefractOutput"]),
        .testTarget(name: "RefractGoldenTests", dependencies: ["RefractGolden"]),
        .target(
            name: "RefractGolden",
            dependencies: ["RefractFrontend", "RefractMapping", "RefractCompose", "RefractArkUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
