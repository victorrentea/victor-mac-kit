// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VictorMacKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VictorMacKit", targets: ["VictorMacKit"]),
    ],
    targets: [
        .target(name: "VictorMacKit"),
        .testTarget(name: "VictorMacKitTests", dependencies: ["VictorMacKit"]),
    ]
)
