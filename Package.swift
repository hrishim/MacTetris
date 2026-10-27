// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTetris",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tetris",
            path: "Sources/Tetris"
        )
    ]
)
