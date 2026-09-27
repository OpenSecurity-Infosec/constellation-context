// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Context",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ContextDomain", targets: ["ContextDomain"]),
        .library(name: "ContextMath", targets: ["ContextMath"]),
        .library(name: "ContextStore", targets: ["ContextStore"]),
        .library(name: "ContextExport", targets: ["ContextExport"]),
        .executable(name: "Context", targets: ["ContextApp"]),
    ],
    targets: [
        .target(name: "ContextDomain"),
        .target(name: "ContextMath", dependencies: ["ContextDomain"]),
        .target(name: "ContextStore", dependencies: ["ContextDomain"]),
        .target(name: "ContextExport", dependencies: ["ContextDomain"]),
        .executableTarget(
            name: "ContextApp",
            dependencies: ["ContextDomain", "ContextMath", "ContextStore", "ContextExport"],
            path: "Apps/Context"
        ),
        .testTarget(name: "ContextDomainTests", dependencies: ["ContextDomain"], path: "Tests/ContextDomainTests"),
        .testTarget(name: "ContextMathTests", dependencies: ["ContextMath", "ContextDomain"], path: "Tests/ContextMathTests"),
    ]
)
