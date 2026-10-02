// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hushel",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "Hushel", path: "Sources")
    ]
)
