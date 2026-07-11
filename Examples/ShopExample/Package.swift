// swift-tools-version: 6.2
import PackageDescription

// The decoupling proof: every feature target depends ONLY on NavigatorKit
// (plus, at most, another feature's tiny *interface* target holding just its
// routes). No feature imports another feature's implementation, and none of
// them know the app shell exists.
let package = Package(
    name: "ShopExample",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // Routes-only interface target: lets other features *link to*
        // reviews without depending on the reviews implementation.
        .target(
            name: "ReviewsInterface",
            dependencies: [.product(name: "NavigatorKit", package: "Navigation")]
        ),
        .target(
            name: "ProductsFeature",
            dependencies: [
                "ReviewsInterface",
                .product(name: "NavigatorKit", package: "Navigation"),
            ]
        ),
        .target(
            name: "ReviewsFeature",
            dependencies: [
                "ReviewsInterface",
                .product(name: "NavigatorKit", package: "Navigation"),
            ]
        ),
        .target(
            name: "SettingsFeature",
            dependencies: [.product(name: "NavigatorKit", package: "Navigation")]
        ),
        .target(
            name: "SearchFeature",
            dependencies: [.product(name: "NavigatorKit", package: "Navigation")]
        ),
        // The app shell: the only place where features are composed.
        .executableTarget(
            name: "ShopApp",
            dependencies: [
                "ProductsFeature",
                "ReviewsFeature",
                "ReviewsInterface",
                "SettingsFeature",
                "SearchFeature",
                .product(name: "NavigatorKit", package: "Navigation"),
            ]
        ),
    ]
)
