// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ALRPackages",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CoreTypes", targets: ["CoreTypes"]),
        .library(name: "Analyzers", targets: ["Analyzers"]),
        .executable(name: "classify-csv", targets: ["ClassifyCSV"]),
    ],
    targets: [
        .target(name: "CoreTypes", dependencies: []),
        .testTarget(name: "CoreTypesTests", dependencies: ["CoreTypes"]),
        .target(name: "Analyzers", dependencies: ["CoreTypes"]),
        .testTarget(name: "AnalyzersTests", dependencies: ["Analyzers", "CoreTypes"]),
        .executableTarget(name: "ClassifyCSV", dependencies: ["Analyzers", "CoreTypes"]),
    ]
)
