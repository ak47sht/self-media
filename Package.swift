// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawMedia",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenClawMedia", targets: ["OpenClawMedia"])
    ],
    targets: [
        .executableTarget(name: "OpenClawMedia", path: "Sources/OpenClawMedia")
    ]
)
