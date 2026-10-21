// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Soroban",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Soroban", path: "Sources/Soroban")
    ]
)
