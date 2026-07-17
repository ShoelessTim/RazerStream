// swift-tools-version: 6.0
import PackageDescription

// The protocol layer, standalone: serial transport, WebSocket framing,
// device commands and events for the Razer Stream Controller. Depend on
// this alone (via a local path dependency, or a git URL once it has its
// own repo) to talk to the hardware from any Swift program; no AppKit or
// SwiftUI involved.

let package = Package(
    name: "RazerStreamKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RazerStreamKit", targets: ["RazerStreamKit"]),
    ],
    targets: [
        .target(
            name: "RazerStreamKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(
            name: "RazerStreamKitTests",
            dependencies: ["RazerStreamKit"]
        ),
    ]
)
