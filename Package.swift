// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reversi3D",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Reversi3D",
            resources: [
                .copy("Resources/Shaders"),
                .copy("Resources/reversi3d.png"),
            ]
        ),
    ]
)
