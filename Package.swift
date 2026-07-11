// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NavigatorKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "NavigatorKit", targets: ["NavigatorKit"])
    ],
    targets: [
        .target(name: "NavigatorKit"),
        .testTarget(name: "NavigatorKitTests", dependencies: ["NavigatorKit"]),
    ]
)
