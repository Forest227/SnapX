// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SnapBoard",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SnapBoard",
            targets: ["SnapBoard"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SnapBoard",
            path: "Sources/SnapBoard"
        ),
    ]
)
