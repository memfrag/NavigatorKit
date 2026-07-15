// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NavigatorKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "NavigatorKit", targets: ["NavigatorKit"])
    ],
    targets: [
        .target(name: "NavigatorKit"),
        .testTarget(name: "NavigatorKitTests", dependencies: ["NavigatorKit"]),
    ]
)
