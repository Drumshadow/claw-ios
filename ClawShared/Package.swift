// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawShared",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ClawShared", targets: ["ClawShared"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "ClawShared", dependencies: []),
    ]
)
