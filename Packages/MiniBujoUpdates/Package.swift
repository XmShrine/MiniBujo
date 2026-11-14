// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniBujoUpdates",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MiniBujoUpdates", targets: ["MiniBujoUpdates"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "MiniBujoUpdates", dependencies: [
            .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))
        ])
    ]
)
