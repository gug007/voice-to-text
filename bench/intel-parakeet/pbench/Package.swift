// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pbench",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", revision: "4ef33f0b64837c2943e8cd0f66940d5861176d6a")
    ],
    targets: [
        .executableTarget(name: "pbench", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ]
)
