// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RazerStream",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RazerStreamKit", targets: ["RazerStreamKit"]),
        .executable(name: "rstream", targets: ["RazerStreamCLI"]),
    ],
    targets: [
        .target(
            name: "RazerStreamKit",
            path: "Sources/RazerStreamKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "RazerStreamCLI",
            dependencies: ["RazerStreamKit"],
            path: "Sources/RazerStreamCLI"
        ),
        .testTarget(
            name: "RazerStreamKitTests",
            dependencies: ["RazerStreamKit"],
            path: "Tests/RazerStreamKitTests"
        ),
    ]
)
