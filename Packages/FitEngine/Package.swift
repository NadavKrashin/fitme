// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FitEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FitEngine", targets: ["FitEngine"]),
    ],
    targets: [
        .target(name: "FitEngine"),
        .testTarget(
            name: "FitEngineTests",
            dependencies: ["FitEngine"],
            resources: [.process("Fixtures")]
        ),
    ]
)
