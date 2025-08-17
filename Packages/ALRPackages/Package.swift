// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ALRPackages",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CoreTypes", targets: ["CoreTypes"]),
        .library(name: "Analyzers", targets: ["Analyzers"]),
    ],
    targets: [
        .target(name: "CoreTypes", dependencies: []),
        .testTarget(name: "CoreTypesTests", dependencies: ["CoreTypes"]),
        .target(name: "Analyzers", dependencies: ["CoreTypes"]),
        .testTarget(name: "AnalyzersTests", dependencies: ["Analyzers", "CoreTypes"]),
    ]
)
