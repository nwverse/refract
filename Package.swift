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
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(name: "RefractMapping", dependencies: ["RefractIR"]),
        .target(name: "RefractCompose", dependencies: ["RefractIR", "RefractMapping"]),
        .target(name: "RefractArkUI", dependencies: ["RefractIR", "RefractMapping"]),
        .executableTarget(
            name: "RefractCLI",
            dependencies: ["RefractIR", "RefractFrontend", "RefractMapping", "RefractCompose", "RefractArkUI"]
        ),
        .testTarget(name: "RefractIRTests", dependencies: ["RefractIR"]),
        .testTarget(name: "RefractFrontendTests", dependencies: ["RefractFrontend"]),
        .testTarget(name: "RefractMappingTests", dependencies: ["RefractMapping"]),
        .testTarget(name: "RefractComposeTests", dependencies: ["RefractCompose"]),
        .testTarget(name: "RefractArkUITests", dependencies: ["RefractArkUI"]),
        .testTarget(name: "RefractCLITests"),
        .testTarget(name: "RefractGoldenTests", dependencies: ["RefractGolden"]),
        .target(
            name: "RefractGolden",
            dependencies: ["RefractFrontend", "RefractMapping", "RefractCompose", "RefractArkUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
