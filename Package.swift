// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpectralLifter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpectralLifter", targets: ["SpectralLifter"])
    ],
    targets: [
        .executableTarget(
            name: "SpectralLifter",
            path: "Sources/SpectralLifter"
        ),
        .testTarget(
            name: "SpectralLifterTests",
            dependencies: ["SpectralLifter"],
            path: "Tests/SpectralLifterTests"
        )
    ]
)
