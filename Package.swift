// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Context",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ContextDomain", targets: ["ContextDomain"]),
        .library(name: "ContextMath", targets: ["ContextMath"]),
        .library(name: "ContextVault", targets: ["ContextVault"]),
        .library(name: "ContextStore", targets: ["ContextStore"]),
        .library(name: "ContextHarness", targets: ["ContextHarness"]),
        .library(name: "ContextExport", targets: ["ContextExport"]),
        .executable(name: "Context", targets: ["ContextApp"]),
    ],
    targets: [
        .target(name: "ContextDomain"),
        .target(name: "ContextMath", dependencies: ["ContextDomain"]),
        .target(name: "ContextVault"),
        .target(name: "ContextStore", dependencies: ["ContextDomain", "ContextVault"]),
        .target(name: "ContextHarness", dependencies: ["ContextStore", "ContextVault"]),
        .target(name: "ContextExport", dependencies: ["ContextDomain"]),
        .executableTarget(
            name: "ContextApp",
            dependencies: ["ContextDomain", "ContextMath", "ContextVault", "ContextStore", "ContextHarness", "ContextExport"],
            path: "Apps/Context"
        ),
        .testTarget(name: "ContextDomainTests", dependencies: ["ContextDomain", "ContextExport"], path: "Tests/ContextDomainTests"),
        .testTarget(name: "ContextMathTests", dependencies: ["ContextMath", "ContextDomain"], path: "Tests/ContextMathTests"),
        .testTarget(name: "ContextStoreTests", dependencies: ["ContextStore", "ContextDomain", "ContextVault"], path: "Tests/ContextStoreTests"),
        .testTarget(name: "ContextHarnessTests", dependencies: ["ContextHarness", "ContextStore", "ContextVault", "ContextDomain"], path: "Tests/ContextHarnessTests"),
        .testTarget(name: "ContextVaultTests", dependencies: ["ContextVault"], path: "Tests/ContextVaultTests"),
    ]
)
