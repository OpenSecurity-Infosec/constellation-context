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
        .library(name: "ContextAI", targets: ["ContextAI"]),
        .library(name: "ContextExport", targets: ["ContextExport"]),
        .executable(name: "context-bench", targets: ["ContextBench"]),
        .executable(name: "Context", targets: ["ContextApp"]),
    ],
    targets: [
        .executableTarget(name: "ContextBench", dependencies: ["ContextVault"]),
        .target(name: "ContextDomain"),
        .target(name: "ContextMath", dependencies: ["ContextDomain"]),
        .target(name: "ContextVault"),
        .target(name: "ContextStore", dependencies: ["ContextDomain", "ContextVault"]),
        .target(name: "ContextHarness", dependencies: ["ContextStore", "ContextVault"]),
        .target(name: "ContextAI"),
        .target(name: "ContextExport", dependencies: ["ContextDomain"]),
        .executableTarget(
            name: "ContextApp",
            dependencies: ["ContextDomain", "ContextMath", "ContextVault", "ContextStore", "ContextHarness", "ContextAI", "ContextExport"],
            path: "Apps/Context"
        ),
        .testTarget(name: "ContextDomainTests", dependencies: ["ContextDomain", "ContextExport"], path: "Tests/ContextDomainTests"),
        .testTarget(name: "ContextMathTests", dependencies: ["ContextMath", "ContextDomain"], path: "Tests/ContextMathTests"),
        .testTarget(name: "ContextAppTests", dependencies: ["ContextApp", "ContextStore", "ContextVault", "ContextDomain"], path: "Tests/ContextAppTests"),
        .testTarget(name: "ContextStoreTests", dependencies: ["ContextStore", "ContextDomain", "ContextVault"], path: "Tests/ContextStoreTests"),
        .testTarget(name: "ContextHarnessTests", dependencies: ["ContextHarness", "ContextStore", "ContextVault", "ContextDomain"], path: "Tests/ContextHarnessTests"),
        .testTarget(name: "ContextAITests", dependencies: ["ContextAI"], path: "Tests/ContextAITests"),
        .testTarget(name: "ContextVaultTests", dependencies: ["ContextVault"], path: "Tests/ContextVaultTests"),
    ]
)
