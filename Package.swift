// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScopedFind",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ScopedFind", targets: ["ScopedFind"])
    ],
    targets: [
        .target(
            name: "ScopedFind",
            path: "ScopedFind",
            exclude: [
                "App",
                "Assets.xcassets",
                "Views"
            ],
            sources: [
                "Models",
                "Services",
                "ViewModels"
            ]
        ),
        .testTarget(
            name: "ScopedFindTests",
            dependencies: ["ScopedFind"],
            path: "ScopedFindTests"
        )
    ]
)
