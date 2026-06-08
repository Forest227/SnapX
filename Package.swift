// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SnapX",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SnapX",
            targets: ["SnapX"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "SnapX",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SnapX"
        ),
    ]
)
