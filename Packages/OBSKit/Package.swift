// swift-tools-version: 6.0
import PackageDescription

// OBS Studio WebSocket (v5) client and status model, standalone: no AppKit,
// no SwiftUI, no device code. RazerStream uses it to drive status LEDs and
// tiles from OBS; anything else on the Mac can depend on it the same way.

let package = Package(
    name: "OBSKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OBSKit", targets: ["OBSKit"]),
    ],
    targets: [
        .target(name: "OBSKit"),
        .testTarget(name: "OBSKitTests", dependencies: ["OBSKit"]),
    ]
)
