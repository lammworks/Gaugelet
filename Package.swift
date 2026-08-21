// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Gaugelet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Gaugelet", targets: ["Gaugelet"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        )
    ],
    targets: [
        .executableTarget(
            name: "Gaugelet",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Gaugelet"
        ),
        .testTarget(
            name: "GaugeletTests",
            dependencies: ["Gaugelet"],
            path: "Tests/GaugeletTests"
        )
    ]
)
