// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GalleryCast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GalleryCast",
            path: "Sources/GalleryCast"
        ),
        .testTarget(
            name: "GalleryCastTests",
            dependencies: ["GalleryCast"],
            path: "Tests/GalleryCastTests"
        ),
    ]
)
