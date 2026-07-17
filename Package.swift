// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RazerStream",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "rstream", targets: ["RazerStreamCLI"]),
        .executable(name: "RazerStreamApp", targets: ["RazerStreamApp"]),
    ],
    dependencies: [
        // The protocol layer lives in its own package so other apps can
        // depend on just it; local path for now, a git URL once it has its
        // own repo.
        .package(path: "Packages/RazerStreamKit"),
    ],
    targets: [
        .executableTarget(
            name: "RazerStreamCLI",
            dependencies: [.product(name: "RazerStreamKit", package: "RazerStreamKit")],
            path: "Sources/RazerStreamCLI"
        ),
        .executableTarget(
            name: "RazerStreamApp",
            dependencies: [.product(name: "RazerStreamKit", package: "RazerStreamKit")],
            path: "Sources/RazerStreamApp"
        ),
    ]
)
