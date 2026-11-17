// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RefractConsumer",
    products: [.library(name: "RefractConsumer", targets: ["RefractConsumer"])],
    dependencies: [.package(path: "../refract")],
    targets: [
        .target(
            name: "RefractConsumer",
            exclude: ["refract.json", "strings.xml", "string.json"],
            plugins: [.plugin(name: "RefractSwiftPMPlugin", package: "refract")]
        ),
    ]
)
