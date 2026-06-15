// swift-tools-version: 5.9
import PackageDescription

// MediaLib (rebased from Again0521/MediaLib for personal use).
// Three targets:
//   - MediaLibCore : pure Foundation/AppKit/SQLite3 model + service + SQLite repository layer
//   - MediaLib     : the macOS SwiftUI app executable (libmpv loaded at runtime via dlopen)
//   - MediaLibChecks: a runnable assertion harness used as Linux-side CI gate
let package = Package(
    name: "MediaLib",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MediaLib", targets: ["MediaLib"]),
        .executable(name: "MediaLibChecks", targets: ["MediaLibChecks"]),
        .library(name: "MediaLibCore", targets: ["MediaLibCore"])
    ],
    targets: [
        .target(
            name: "MediaLibCore",
            path: "Sources/MediaLibCore"
        ),
        .executableTarget(
            name: "MediaLib",
            dependencies: ["MediaLibCore"],
            path: "Sources/MediaLib",
            // Icons are bundled into the .app by scripts/medialib/package_dmg.sh,
            // not via Bundle.module, so keep them out of SwiftPM resource processing.
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "MediaLibChecks",
            dependencies: ["MediaLibCore"],
            path: "Sources/MediaLibChecks"
        )
    ]
)
