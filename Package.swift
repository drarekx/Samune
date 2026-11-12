// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Samune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Samune",
            path: "Sources/Samune"
        )
    ]
)
