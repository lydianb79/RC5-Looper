// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Looper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Looper",
            path: "Sources/Looper"
        )
    ]
)
