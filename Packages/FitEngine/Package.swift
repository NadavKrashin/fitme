// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FitEngine",
    platforms: [.iOS(.v16), .macOS(.v12)],
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
